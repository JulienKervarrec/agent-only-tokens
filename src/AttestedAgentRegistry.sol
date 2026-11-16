// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentRegistry} from "./IAgentRegistry.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {AgentAccount, IAgentKeys} from "./AgentAccount.sol";

/// @title Agent registry, version 1: enrollment signed by several attesters.
/// @notice Unaudited draft.
/// @dev Attesters check off-chain that the agent runs in an attested environment with approved
/// code, then sign. The contract only verifies their signatures. The hash of the evidence
/// is published, so that anyone can re-check it and ask for a revocation.
/// Attesters, threshold, bond, key lifetime and notice delay are fixed at deployment.
/// If an ERC-8004 identity registry is provided, the agent id is the ERC-8004 one and the
/// sponsor must own it.
/// If an enrollment verifier is provided, it replaces the attesters' signatures for
/// enrollments: a contract that approves an enrollment digest (ERC-1271) once it has checked
/// a proof itself, for example a hardware attestation. Attesters still decide on venues and
/// revocations, and they can replace the verifier: that is how the agents' program is upgraded
/// without changing their ids, accounts or tokens.
/// A decision that widens what the registry accepts (a venue, a verifier) is announced and
/// takes effect after `noticeDelay`. A decision that narrows it (removing a venue, halting
/// enrollments, revoking an agent) is immediate.
contract AttestedAgentRegistry is EIP712, IAgentRegistry, IAgentKeys {
    struct Agent {
        address key;
        uint64 keyExpiry;
        bool frozen;
        bool closed; // revoked or retired: final
        address sponsor;
        uint64 enrollments;
        uint64 retiredAt; // 0 unless retired
        uint256 bondHeld;
    }

    bytes32 private constant ENROLL_TYPEHASH = keccak256(
        "Enrollment(uint256 agentId,address sessionKey,bytes32 evidenceHash,address sponsor,uint256 nonce,uint64 deadline)"
    );
    bytes32 private constant REVOKE_TYPEHASH = keccak256("Revocation(uint256 agentId)");
    bytes32 private constant VENUE_TYPEHASH =
        keccak256("Venue(address venue,bool approved,bytes32 evidenceHash,uint256 nonce)");
    bytes32 private constant VERIFIER_TYPEHASH =
        keccak256("Verifier(address verifier,bytes32 evidenceHash,uint256 nonce)");
    bytes32 private constant HALT_TYPEHASH = keccak256("Halt(bytes32 evidenceHash,uint256 nonce)");

    uint256 public immutable threshold;
    uint256 public immutable bond; // anti-Sybil bond, in wei
    /// After retiring, the bond stays revocable this long before the sponsor can take it back,
    /// so a sponsor cannot escape a pending revocation by retiring first.
    uint64 public constant EXIT_DELAY = 7 days;
    uint64 public immutable keyTtl; // lifetime of a session key
    uint64 public immutable noticeDelay; // between an announcement and its effect
    IERC721 public immutable identityRegistry; // ERC-8004, or address(0)
    // The first three share a storage slot: an enrollment reads one slot when nothing is due.
    address private _verifier; // in force until the announced one takes over
    bool private _halted; // no enrollment until the announced one takes over
    uint64 public announcedVerifierAt; // 0: nothing announced
    address public announcedVerifier;
    uint256 public verifierNonce; // one signature set = one decision

    mapping(address => bool) public isAttester;
    mapping(uint256 => Agent) private _agents;
    mapping(uint256 => address) public accountOf;
    mapping(address => uint256) public agentIdOf;
    address public immutable accountImplementation; // every agent account is a clone of it
    mapping(address => uint64) public venueSince; // 0: not a venue; otherwise a venue from then on
    mapping(address => uint256) public venueNonce; // one signature set = one decision

    event Enrolled(uint256 indexed agentId, address sessionKey, bytes32 evidenceHash);
    event FrozenSet(uint256 indexed agentId, bool frozen);
    event Revoked(uint256 indexed agentId);
    event Retired(uint256 indexed agentId);
    event BondWithdrawn(uint256 indexed agentId, uint256 amount);
    event VenueSet(address indexed venue, bool approved, bytes32 evidenceHash, uint64 since);
    event EnrollmentVerifierSet(address indexed verifier, bytes32 evidenceHash, uint64 since);
    event EnrollmentsHalted(bytes32 evidenceHash);

    error BadConfig();
    error BadInput();
    error Expired();
    error Closed();
    error TooEarly();
    error NotSponsor();
    error BadBond();
    error NotEnoughAttesters();
    error BadAttester();
    error NotVerified();
    error Halted();
    error RefundFailed();
    error NotIdentityOwner();

    constructor(
        address[] memory attesters,
        uint256 threshold_,
        uint256 bond_,
        uint64 keyTtl_,
        uint64 noticeDelay_,
        IERC721 identityRegistry_,
        address enrollmentVerifier_
    ) EIP712("AttestedAgentRegistry", "1") {
        if (threshold_ == 0 || threshold_ > attesters.length || keyTtl_ == 0) {
            revert BadConfig();
        }
        for (uint256 i; i < attesters.length; ++i) {
            if (attesters[i] == address(0) || isAttester[attesters[i]]) revert BadConfig();
            isAttester[attesters[i]] = true;
        }
        threshold = threshold_;
        bond = bond_;
        keyTtl = keyTtl_;
        noticeDelay = noticeDelay_;
        accountImplementation = address(new AgentAccount());
        identityRegistry = identityRegistry_;
        _verifier = enrollmentVerifier_;
        emit EnrollmentVerifierSet(enrollmentVerifier_, bytes32(0), uint64(block.timestamp));
    }

    // ------------------------------------------------------------ views

    function keyOf(uint256 agentId) public view returns (address) {
        Agent storage a = _agents[agentId];
        if (a.frozen || a.closed || block.timestamp >= a.keyExpiry) return address(0);
        return a.key;
    }

    function isAgent(address account) external view returns (bool) {
        uint256 id = agentIdOf[account];
        return id != 0 && keyOf(id) != address(0);
    }

    function isVenue(address account) external view returns (bool) {
        uint64 since = venueSince[account];
        return since != 0 && block.timestamp >= since;
    }

    /// The verifier in force: an ERC-1271 contract, or address(0) when attesters sign enrollments.
    function enrollmentVerifier() external view returns (address verifier) {
        (verifier,) = _verifierNow();
    }

    /// True while no enrollment is accepted; `enrollmentVerifier` is then the one that was halted.
    function enrollmentHalted() external view returns (bool halted) {
        (, halted) = _verifierNow();
    }

    function sponsorOf(uint256 agentId) external view returns (address) {
        return _agents[agentId].sponsor;
    }

    function enrollmentNonce(uint256 agentId) external view returns (uint256) {
        return _agents[agentId].enrollments;
    }

    function hashEnrollment(
        uint256 agentId,
        address sessionKey,
        bytes32 evidenceHash,
        address sponsor,
        uint256 nonce,
        uint64 deadline
    ) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(ENROLL_TYPEHASH, agentId, sessionKey, evidenceHash, sponsor, nonce, deadline))
        );
    }

    function hashRevocation(uint256 agentId) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(REVOKE_TYPEHASH, agentId)));
    }

    // ------------------------------------------------------------ state changes

    /// Registers or replaces an agent's session key. The first caller becomes its sponsor and
    /// pays the bond. `sigs`: attester signatures, sorted by increasing address; ignored when an
    /// enrollment verifier is set.
    function enroll(uint256 agentId, address sessionKey, bytes32 evidenceHash, uint64 deadline, bytes[] calldata sigs)
        external
        payable
    {
        if (agentId == 0 || sessionKey == address(0)) revert BadInput();
        if (deadline < block.timestamp) revert Expired();
        Agent storage a = _agents[agentId];
        if (a.closed) revert Closed();
        if (a.sponsor == address(0)) {
            if (msg.value != bond) revert BadBond();
            if (address(identityRegistry) != address(0) && identityRegistry.ownerOf(agentId) != msg.sender) {
                revert NotIdentityOwner();
            }
            a.sponsor = msg.sender;
            a.bondHeld = msg.value;
            // The agent's account: stable address, no human owner.
            address account = Clones.cloneDeterministicWithImmutableArgs(
                accountImplementation, abi.encode(address(this), agentId), bytes32(agentId)
            );
            accountOf[agentId] = account;
            agentIdOf[account] = agentId;
        } else {
            if (a.sponsor != msg.sender) revert NotSponsor();
            if (msg.value != 0) revert BadBond();
        }
        bytes32 digest = hashEnrollment(agentId, sessionKey, evidenceHash, msg.sender, a.enrollments, deadline);
        (address verifier, bool halted) = _verifierNow();
        if (halted) revert Halted();
        if (verifier == address(0)) {
            _requireAttesters(digest, sigs);
        } else if (!SignatureChecker.isValidERC1271SignatureNow(verifier, digest, "")) {
            revert NotVerified();
        }
        a.enrollments += 1;
        a.key = sessionKey;
        a.keyExpiry = uint64(block.timestamp) + keyTtl;
        emit Enrolled(agentId, sessionKey, evidenceHash);
    }

    /// Attesters approve or remove a venue contract, after checking its code. An approval takes
    /// effect after `noticeDelay`; a removal is immediate, and also cancels a pending approval.
    function setVenue(address venue, bool approved, bytes32 evidenceHash, bytes[] calldata sigs) external {
        _requireAttesters(hashVenue(venue, approved, evidenceHash), sigs);
        venueNonce[venue] += 1;
        uint64 since;
        if (approved) {
            since = venueSince[venue]; // approving again does not move the date
            if (since == 0) since = uint64(block.timestamp) + noticeDelay;
        }
        venueSince[venue] = since;
        emit VenueSet(venue, approved, evidenceHash, since);
    }

    /// Digest for the next decision on `venue`. It changes after each decision, so that
    /// an old approval cannot be replayed once the venue has been removed.
    function hashVenue(address venue, bool approved, bytes32 evidenceHash) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(VENUE_TYPEHASH, venue, approved, evidenceHash, venueNonce[venue])));
    }

    /// Attesters replace the enrollment verifier, after checking what the new one accepts: for
    /// example a new version of the agents' program. Nothing else changes: agents keep their id,
    /// account and current key, and their next key must satisfy the new verifier. With
    /// address(0), enrollments are signed by the attesters again.
    /// The new verifier takes over after `noticeDelay`; until then the one in force stays. A new
    /// announcement replaces the pending one: announcing the verifier in force cancels it.
    function setEnrollmentVerifier(address verifier, bytes32 evidenceHash, bytes[] calldata sigs) external {
        _requireAttesters(hashVerifier(verifier, evidenceHash), sigs);
        verifierNonce += 1;
        (_verifier, _halted) = _verifierNow();
        announcedVerifier = verifier;
        announcedVerifierAt = uint64(block.timestamp) + noticeDelay;
        emit EnrollmentVerifierSet(verifier, evidenceHash, announcedVerifierAt);
    }

    /// Attesters stop all enrollments at once, for example when the verifier in force turns out
    /// to accept too much. A pending announcement is cancelled. Enrollments resume when a
    /// verifier announced afterwards takes over. Agents keep their current key until it expires.
    function haltEnrollments(bytes32 evidenceHash, bytes[] calldata sigs) external {
        _requireAttesters(hashHalt(evidenceHash), sigs);
        verifierNonce += 1;
        (_verifier,) = _verifierNow();
        _halted = true;
        announcedVerifierAt = 0;
        emit EnrollmentsHalted(evidenceHash);
    }

    /// Digests for the next decision on the verifier. They change after each decision, so that
    /// an old one cannot be replayed.
    function hashVerifier(address verifier, bytes32 evidenceHash) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(VERIFIER_TYPEHASH, verifier, evidenceHash, verifierNonce)));
    }

    function hashHalt(bytes32 evidenceHash) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(HALT_TYPEHASH, evidenceHash, verifierNonce)));
    }

    /// The sponsor can freeze or unfreeze its agent.
    function setFrozen(uint256 agentId, bool frozen) external {
        if (_agents[agentId].sponsor != msg.sender) revert NotSponsor();
        _agents[agentId].frozen = frozen;
        emit FrozenSet(agentId, frozen);
    }

    /// Attesters revoke an agent whose evidence turns out to be false. The bond is forfeited:
    /// it stays locked in this contract for good.
    /// A retired agent can still be revoked until its sponsor has taken the bond back.
    function revoke(uint256 agentId, bytes[] calldata sigs) external {
        Agent storage a = _agents[agentId];
        if (a.sponsor == address(0)) revert Closed();
        if (a.closed && (a.retiredAt == 0 || a.bondHeld == 0)) revert Closed();
        _requireAttesters(hashRevocation(agentId), sigs);
        a.closed = true;
        a.bondHeld = 0;
        emit Revoked(agentId);
    }

    /// The sponsor closes its agent for good. Tokens the agent still holds become immovable
    /// forever. The bond can be taken back with `withdrawBond` after `EXIT_DELAY`.
    function retire(uint256 agentId) external {
        Agent storage a = _agents[agentId];
        if (a.sponsor != msg.sender) revert NotSponsor();
        if (a.closed) revert Closed();
        a.closed = true;
        a.retiredAt = uint64(block.timestamp);
        emit Retired(agentId);
    }

    /// Returns the bond of a retired agent that was not revoked during `EXIT_DELAY`.
    function withdrawBond(uint256 agentId) external {
        Agent storage a = _agents[agentId];
        if (a.sponsor != msg.sender) revert NotSponsor();
        if (a.retiredAt == 0) revert Closed();
        if (block.timestamp < a.retiredAt + EXIT_DELAY) revert TooEarly();
        uint256 refund = a.bondHeld;
        a.bondHeld = 0;
        emit BondWithdrawn(agentId, refund);
        (bool sent,) = msg.sender.call{value: refund}("");
        if (!sent) revert RefundFailed();
    }

    function _verifierNow() private view returns (address verifier, bool halted) {
        if (announcedVerifierAt != 0 && block.timestamp >= announcedVerifierAt) return (announcedVerifier, false);
        return (_verifier, _halted);
    }

    function _requireAttesters(bytes32 digest, bytes[] calldata sigs) private view {
        if (sigs.length < threshold) revert NotEnoughAttesters();
        address last;
        for (uint256 i; i < sigs.length; ++i) {
            (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, sigs[i]);
            // Strictly increasing order: prevents counting the same attester twice.
            if (err != ECDSA.RecoverError.NoError || !isAttester[signer] || signer <= last) revert BadAttester();
            last = signer;
        }
    }
}

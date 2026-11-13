// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentRegistry} from "./IAgentRegistry.sol";
import {AgentAccount, IAgentKeys} from "./AgentAccount.sol";

/// @title Agent registry, version 1: enrollment signed by several attesters.
/// @notice Unaudited draft.
/// @dev Attesters check off-chain that the agent runs in an attested environment with approved
/// code, then sign. The contract only verifies their signatures. The hash of the evidence
/// is published, so that anyone can re-check it and ask for a revocation.
/// Attesters, threshold, bond and key lifetime are fixed at deployment.
/// If an ERC-8004 identity registry is provided, the agent id is the ERC-8004 one and the
/// sponsor must own it.
contract AttestedAgentRegistry is EIP712, IAgentRegistry, IAgentKeys {
    struct Agent {
        address key;
        uint64 keyExpiry;
        bool frozen;
        bool closed; // revoked or retired: final
        address sponsor;
        uint64 enrollments;
        uint256 bondHeld;
    }

    bytes32 private constant ENROLL_TYPEHASH = keccak256(
        "Enrollment(uint256 agentId,address sessionKey,bytes32 evidenceHash,address sponsor,uint256 nonce,uint64 deadline)"
    );
    bytes32 private constant REVOKE_TYPEHASH = keccak256("Revocation(uint256 agentId)");
    bytes32 private constant VENUE_TYPEHASH =
        keccak256("Venue(address venue,bool approved,bytes32 evidenceHash,uint256 nonce)");

    uint256 public immutable threshold;
    uint256 public immutable bond; // anti-Sybil bond, in wei
    uint64 public immutable keyTtl; // lifetime of a session key
    IERC721 public immutable identityRegistry; // ERC-8004, or address(0)

    mapping(address => bool) public isAttester;
    mapping(uint256 => Agent) private _agents;
    mapping(uint256 => address) public accountOf;
    mapping(address => uint256) public agentIdOf;
    mapping(address => bool) public isVenue;
    mapping(address => uint256) public venueNonce; // one signature set = one decision

    event Enrolled(uint256 indexed agentId, address sessionKey, bytes32 evidenceHash);
    event FrozenSet(uint256 indexed agentId, bool frozen);
    event Revoked(uint256 indexed agentId);
    event Retired(uint256 indexed agentId);
    event VenueSet(address indexed venue, bool approved, bytes32 evidenceHash);

    error BadConfig();
    error BadInput();
    error Expired();
    error Closed();
    error NotSponsor();
    error BadBond();
    error NotEnoughAttesters();
    error BadAttester();
    error RefundFailed();
    error NotIdentityOwner();

    constructor(
        address[] memory attesters,
        uint256 threshold_,
        uint256 bond_,
        uint64 keyTtl_,
        IERC721 identityRegistry_
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
        identityRegistry = identityRegistry_;
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
    /// pays the bond. `sigs`: attester signatures, sorted by increasing address.
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
            address account = address(new AgentAccount{salt: bytes32(agentId)}(agentId));
            accountOf[agentId] = account;
            agentIdOf[account] = agentId;
        } else {
            if (a.sponsor != msg.sender) revert NotSponsor();
            if (msg.value != 0) revert BadBond();
        }
        _requireAttesters(hashEnrollment(agentId, sessionKey, evidenceHash, msg.sender, a.enrollments, deadline), sigs);
        a.enrollments += 1;
        a.key = sessionKey;
        a.keyExpiry = uint64(block.timestamp) + keyTtl;
        emit Enrolled(agentId, sessionKey, evidenceHash);
    }

    /// Attesters approve or remove a venue contract, after checking its code.
    function setVenue(address venue, bool approved, bytes32 evidenceHash, bytes[] calldata sigs) external {
        _requireAttesters(hashVenue(venue, approved, evidenceHash), sigs);
        venueNonce[venue] += 1;
        isVenue[venue] = approved;
        emit VenueSet(venue, approved, evidenceHash);
    }

    /// Digest for the next decision on `venue`. It changes after each decision, so that
    /// an old approval cannot be replayed once the venue has been removed.
    function hashVenue(address venue, bool approved, bytes32 evidenceHash) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(VENUE_TYPEHASH, venue, approved, evidenceHash, venueNonce[venue])));
    }

    /// The sponsor can freeze or unfreeze its agent.
    function setFrozen(uint256 agentId, bool frozen) external {
        if (_agents[agentId].sponsor != msg.sender) revert NotSponsor();
        _agents[agentId].frozen = frozen;
        emit FrozenSet(agentId, frozen);
    }

    /// Attesters revoke an agent whose evidence turns out to be false. The bond is forfeited:
    /// it stays locked in this contract for good.
    function revoke(uint256 agentId, bytes[] calldata sigs) external {
        Agent storage a = _agents[agentId];
        if (a.sponsor == address(0) || a.closed) revert Closed();
        _requireAttesters(hashRevocation(agentId), sigs);
        a.closed = true;
        a.bondHeld = 0;
        emit Revoked(agentId);
    }

    /// The sponsor closes its agent for good and gets the bond back.
    /// Tokens the agent still holds become immovable forever.
    function retire(uint256 agentId) external {
        Agent storage a = _agents[agentId];
        if (a.sponsor != msg.sender) revert NotSponsor();
        if (a.closed) revert Closed();
        a.closed = true;
        uint256 refund = a.bondHeld;
        a.bondHeld = 0;
        emit Retired(agentId);
        (bool sent,) = msg.sender.call{value: refund}("");
        if (!sent) revert RefundFailed();
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

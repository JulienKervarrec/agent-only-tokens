// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IAgentRegistry} from "./AgentOnlyNFT.sol";
import {IAgentSponsors} from "./AgentOnlyNFTWithVault.sol";

/// @title Registre d'agents, version 1 : enrolement signe par plusieurs attesteurs.
/// @notice Brouillon non audite.
/// @dev Les attesteurs verifient hors chaine que l'agent tourne dans un environnement atteste avec un
/// code approuve, puis signent. Le contrat ne verifie que leurs signatures. L'empreinte de la preuve
/// est publiee, pour que n'importe qui puisse la recontroler et demander une revocation.
/// Attesteurs, seuil, caution et duree de validite des cles sont fixes au deploiement.
contract AttestedAgentRegistry is EIP712, IAgentRegistry, IAgentSponsors {
    struct Agent {
        address key;
        uint64 keyExpiry;
        bool frozen;
        bool closed; // revoque ou retire : definitif
        address sponsor;
        uint64 enrollments;
        uint256 bondHeld;
    }

    bytes32 private constant ENROLL_TYPEHASH = keccak256(
        "Enrollment(uint256 agentId,address sessionKey,bytes32 evidenceHash,address sponsor,uint256 nonce,uint64 deadline)"
    );
    bytes32 private constant REVOKE_TYPEHASH = keccak256("Revocation(uint256 agentId)");

    uint256 public immutable threshold;
    uint256 public immutable bond; // caution anti-Sybil, en wei
    uint64 public immutable keyTtl; // duree de validite d'une cle de session

    mapping(address => bool) public isAttester;
    mapping(uint256 => Agent) private _agents;

    event Enrolled(uint256 indexed agentId, address sessionKey, bytes32 evidenceHash);
    event FrozenSet(uint256 indexed agentId, bool frozen);
    event Revoked(uint256 indexed agentId);
    event Retired(uint256 indexed agentId);

    error BadConfig();
    error BadInput();
    error Expired();
    error Closed();
    error NotSponsor();
    error BadBond();
    error NotEnoughAttesters();
    error BadAttester();
    error RefundFailed();

    constructor(address[] memory attesters, uint256 threshold_, uint256 bond_, uint64 keyTtl_)
        EIP712("AttestedAgentRegistry", "1")
    {
        if (threshold_ == 0 || threshold_ > attesters.length || keyTtl_ == 0) revert BadConfig();
        for (uint256 i; i < attesters.length; ++i) {
            if (attesters[i] == address(0) || isAttester[attesters[i]]) revert BadConfig();
            isAttester[attesters[i]] = true;
        }
        threshold = threshold_;
        bond = bond_;
        keyTtl = keyTtl_;
    }

    // ------------------------------------------------------------ lecture

    function keyOf(uint256 agentId) external view returns (address) {
        Agent storage a = _agents[agentId];
        if (a.frozen || a.closed || block.timestamp >= a.keyExpiry) return address(0);
        return a.key;
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

    // ------------------------------------------------------------ ecriture

    /// Inscrit ou remplace la cle de session d'un agent. Le premier appelant devient son sponsor et
    /// depose la caution. `sigs` : signatures d'attesteurs, triees par adresse croissante.
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
            a.sponsor = msg.sender;
            a.bondHeld = msg.value;
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

    /// Le sponsor peut geler ou degeler son agent.
    function setFrozen(uint256 agentId, bool frozen) external {
        if (_agents[agentId].sponsor != msg.sender) revert NotSponsor();
        _agents[agentId].frozen = frozen;
        emit FrozenSet(agentId, frozen);
    }

    /// Les attesteurs revoquent un agent dont la preuve s'avere fausse. La caution est perdue.
    function revoke(uint256 agentId, bytes[] calldata sigs) external {
        Agent storage a = _agents[agentId];
        if (a.sponsor == address(0) || a.closed) revert Closed();
        _requireAttesters(hashRevocation(agentId), sigs);
        a.closed = true;
        a.bondHeld = 0;
        emit Revoked(agentId);
    }

    /// Le sponsor ferme definitivement son agent et recupere la caution.
    /// Les tokens que l'agent detient encore deviennent immobiles pour toujours.
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
            // Ordre strictement croissant : empeche de compter deux fois le meme attesteur.
            if (err != ECDSA.RecoverError.NoError || !isAttester[signer] || signer <= last) revert BadAttester();
            last = signer;
        }
    }
}

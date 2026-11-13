// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// Le seul lien entre le token et la preuve d'agent.
interface IAgentRegistry {
    /// Cle de signature courante de l'agent, ou address(0) s'il n'est pas un agent actif.
    function keyOf(uint256 agentId) external view returns (address);
}

/// @title AgentOnlyNFT : le coeur du standard, sans argent et sans administrateur.
/// @notice Brouillon non audite.
/// @dev Trois regles : (1) les ecritures ERC-721 classiques echouent ; (2) tout changement exige
/// l'intention signee du detenteur, et l'accord du destinataire ; (3) seul un agent reconnu par le
/// registre peut signer ou recevoir.
contract AgentOnlyNFT is EIP712, ReentrancyGuard {
    enum Op { Mint, Transfer, Burn, Lock, Unlock, Claim }

    struct Intent {
        uint8 op;
        uint256 tokenId; // 0 pour un mint
        uint256 agentId; // agent qui signe
        uint256 counterparty; // autre agent, ou 0
        bytes32 termsHash;
        uint256 nonce; // compteur du token, ou compteur de mints de l'agent
        uint64 deadline;
    }

    /// Mint: content. Transfer: amount (prix, 0 = don).
    /// Lock: until, et pour un gage amount (pret) et repay (remboursement).
    struct Terms {
        Op op;
        bytes32 content;
        uint128 amount;
        uint128 repay;
        uint64 until;
    }

    struct Token {
        uint256 agent;
        uint256 locker; // 0 = libre ; = agent : verrou personnel ; autre : gage
        uint64 nonce; // 0 = inexistant
        uint64 lockedUntil;
        uint128 repay;
        bytes32 content;
    }

    struct MintMeter {
        uint64 nonce;
        uint64 windowStart;
        uint32 count;
    }

    struct Ctx {
        Op op;
        uint256 tokenId;
        bytes32 th;
        uint64 nonce;
    }

    bytes32 private constant INTENT_TYPEHASH = keccak256(
        "Intent(uint8 op,uint256 tokenId,uint256 agentId,uint256 counterparty,bytes32 termsHash,uint256 nonce,uint64 deadline)"
    );

    IAgentRegistry public immutable registry;
    // Anti-spam : frais de mint et quota de mints par agent et par periode. Fixes au deploiement.
    uint256 public immutable mintFee;
    address public immutable feeRecipient;
    uint32 public immutable mintQuota;
    uint64 public immutable quotaPeriod;

    mapping(uint256 => Token) private _tokens;
    mapping(uint256 => MintMeter) private _meters;
    mapping(address => uint256) private _balances;
    uint256 private _lastId;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Locked(uint256 tokenId);
    event AgentOp(uint256 indexed tokenId, Op indexed op, uint256 indexed agentId, bytes32 intentHash);

    error TransfersDisabled();
    error PaymentsDisabled();
    error NoToken();
    error BadOp();
    error BadToken();
    error TermsMismatch();
    error BadNonce();
    error Expired();
    error NotAgent();
    error BadSigner();
    error BadParties();
    error NotHolder();
    error NotLocker();
    error TokenLocked();
    error NotLocked();
    error BadTerms();
    error StillLocked();
    error NotDue();
    error BadFee();
    error QuotaExceeded();

    constructor(IAgentRegistry registry_, uint256 mintFee_, address feeRecipient_, uint32 mintQuota_, uint64 quotaPeriod_)
        EIP712("AgentOnlyNFT", "1")
    {
        registry = registry_;
        mintFee = mintFee_;
        feeRecipient = feeRecipient_;
        mintQuota = mintQuota_;
        quotaPeriod = quotaPeriod_;
    }

    // ------------------------------------------------------------ lecture ERC-721

    function name() external pure returns (string memory) {
        return "AgentOnlyNFT";
    }

    function symbol() external pure returns (string memory) {
        return "AONFT";
    }

    /// Adresse stable derivee de l'identifiant d'agent. Aucune cle n'existe pour elle.
    function holderAddress(uint256 agentId) public view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked("agent-only", address(this), agentId)))));
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        Token storage t = _tokens[tokenId];
        if (t.nonce == 0) revert NoToken();
        return holderAddress(t.agent);
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }

    function getApproved(uint256) external pure returns (address) {
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    /// ERC-5192 : toujours verrouille pour les interfaces classiques.
    function locked(uint256 tokenId) external view returns (bool) {
        if (_tokens[tokenId].nonce == 0) revert NoToken();
        return true;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 || id == 0x80ac58cd || id == 0xb45a3c0e; // ERC-165, ERC-721, ERC-5192
    }

    // ------------------------------------------------------------ ecritures ERC-721 : toutes refusees

    function approve(address, uint256) external pure {
        revert TransfersDisabled();
    }

    function setApprovalForAll(address, bool) external pure {
        revert TransfersDisabled();
    }

    function transferFrom(address, address, uint256) external pure {
        revert TransfersDisabled();
    }

    function safeTransferFrom(address, address, uint256) external pure {
        revert TransfersDisabled();
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert TransfersDisabled();
    }

    // ------------------------------------------------------------ vues du profil

    function agentOf(uint256 tokenId) external view returns (uint256) {
        return _tokens[tokenId].agent;
    }

    function nonceOf(uint256 tokenId) external view returns (uint256) {
        return _tokens[tokenId].nonce;
    }

    function mintNonce(uint256 agentId) external view returns (uint256) {
        return _meters[agentId].nonce;
    }

    function contentOf(uint256 tokenId) external view returns (bytes32) {
        return _tokens[tokenId].content;
    }

    function lockOf(uint256 tokenId) external view returns (uint256 locker, uint64 until, uint256 repay) {
        Token storage t = _tokens[tokenId];
        return (t.locker, t.lockedUntil, t.repay);
    }

    function hashIntent(Intent calldata i) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(INTENT_TYPEHASH, i.op, i.tokenId, i.agentId, i.counterparty, i.termsHash, i.nonce, i.deadline)
            )
        );
    }

    function termsHash(Terms calldata t) public pure returns (bytes32) {
        return keccak256(abi.encode(t.op, t.content, t.amount, t.repay, t.until));
    }

    // ------------------------------------------------------------ point d'entree unique

    /// Execute une operation. Une intention par partie, sur les memes termes.
    /// N'importe qui peut appeler : le relais ne peut rien modifier.
    function execute(uint256 tokenId, Terms calldata terms, Intent[] calldata intents, bytes[] calldata sigs)
        external
        payable
        nonReentrant
        returns (uint256)
    {
        Op op = terms.op;
        if (msg.value != (op == Op.Mint ? mintFee : 0)) revert BadFee();

        uint256 n = intents.length;
        // Transfer : deux parties. Lock : une (verrou personnel) ou deux (gage). Le reste : une.
        bool okCount = op == Op.Transfer ? n == 2 : (op == Op.Lock ? (n == 1 || n == 2) : n == 1);
        if (!okCount || sigs.length != n) revert BadParties();

        Ctx memory c = Ctx(op, tokenId, termsHash(terms), 0);
        if (op == Op.Mint) {
            if (tokenId != 0) revert BadToken();
        } else {
            c.nonce = _tokens[tokenId].nonce;
            if (c.nonce == 0) revert NoToken();
        }

        (uint256 p0, bytes32 digest) = _check(c, intents[0], sigs[0]);
        uint256 p1;
        if (n == 2) {
            (p1,) = _check(c, intents[1], sigs[1]);
            if (p0 == p1 || intents[0].counterparty != p1 || intents[1].counterparty != p0) revert BadParties();
        } else if (intents[0].counterparty != 0) {
            revert BadParties();
        }

        if (op == Op.Mint) {
            tokenId = _mintTo(p0, terms.content);
        } else {
            _apply(tokenId, terms, p0, p1);
        }
        emit AgentOp(tokenId, op, p0, digest);

        if (msg.value != 0) {
            (bool sent,) = feeRecipient.call{value: msg.value}("");
            if (!sent) revert BadFee();
        }
        return tokenId;
    }

    function _check(Ctx memory c, Intent calldata i, bytes calldata sig)
        private
        view
        returns (uint256 agentId, bytes32 digest)
    {
        if (i.op != uint8(c.op)) revert BadOp();
        if (i.tokenId != c.tokenId) revert BadToken();
        if (i.termsHash != c.th) revert TermsMismatch();
        agentId = i.agentId;
        // Un mint n'a pas encore de token : son compteur est celui de l'agent.
        if (i.nonce != (c.op == Op.Mint ? _meters[agentId].nonce : c.nonce)) revert BadNonce();
        if (i.deadline < block.timestamp) revert Expired();
        address key = registry.keyOf(agentId);
        if (key == address(0)) revert NotAgent();
        digest = hashIntent(i);
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, sig);
        if (err != ECDSA.RecoverError.NoError || signer != key) revert BadSigner();
    }

    function _mintTo(uint256 agentId, bytes32 content) private returns (uint256 tokenId) {
        MintMeter storage m = _meters[agentId];
        if (block.timestamp >= uint256(m.windowStart) + quotaPeriod) {
            m.windowStart = uint64(block.timestamp);
            m.count = 0;
        }
        if (++m.count > mintQuota) revert QuotaExceeded();
        m.nonce += 1;

        tokenId = ++_lastId;
        Token storage t = _tokens[tokenId];
        t.agent = agentId;
        t.nonce = 1;
        t.content = content;
        address to = holderAddress(agentId);
        _balances[to] += 1;
        emit Transfer(address(0), to, tokenId);
        emit Locked(tokenId);
    }

    function _apply(uint256 tokenId, Terms calldata terms, uint256 p0, uint256 p1) private {
        Token storage t = _tokens[tokenId];
        Op op = terms.op;

        if (op == Op.Transfer || op == Op.Burn || op == Op.Lock) {
            if (p0 != t.agent) revert NotHolder();
            if (t.locker != 0) revert TokenLocked();
        }

        if (op == Op.Transfer) {
            _pay(p1, p0, terms.amount);
            _move(t, tokenId, p1);
        } else if (op == Op.Burn) {
            address from = holderAddress(t.agent);
            _balances[from] -= 1;
            delete _tokens[tokenId];
            emit Transfer(from, address(0), tokenId);
            return;
        } else if (op == Op.Lock) {
            if (terms.until <= block.timestamp) revert BadTerms();
            if (p1 == 0) {
                // Verrou personnel (staking) : pas d'argent.
                if (terms.amount != 0 || terms.repay != 0) revert BadTerms();
                t.locker = p0;
            } else {
                // Gage : le preteur verse le pret et devient le gardien du verrou.
                _pay(p1, p0, terms.amount);
                t.locker = p1;
                t.repay = terms.repay;
            }
            t.lockedUntil = terms.until;
        } else if (op == Op.Unlock) {
            if (t.locker == 0) revert NotLocked();
            if (t.locker == t.agent) {
                if (p0 != t.agent) revert NotHolder();
                if (block.timestamp < t.lockedUntil) revert StillLocked();
            } else if (p0 == t.agent) {
                // Remboursement, possible tant que le preteur n'a pas saisi.
                _pay(p0, t.locker, t.repay);
            } else if (p0 != t.locker) {
                revert NotLocker();
            }
            _clearLock(t);
        } else {
            // Claim : le preteur saisit le token apres l'echeance.
            if (t.locker == 0 || t.locker == t.agent) revert NotLocked();
            if (p0 != t.locker) revert NotLocker();
            if (block.timestamp <= t.lockedUntil) revert NotDue();
            _clearLock(t);
            _move(t, tokenId, p0);
        }
        t.nonce += 1;
    }

    function _clearLock(Token storage t) private {
        t.locker = 0;
        t.lockedUntil = 0;
        t.repay = 0;
    }

    function _move(Token storage t, uint256 tokenId, uint256 toAgent) private {
        address from = holderAddress(t.agent);
        address to = holderAddress(toAgent);
        _balances[from] -= 1;
        _balances[to] += 1;
        t.agent = toAgent;
        emit Transfer(from, to, tokenId);
    }

    /// Le coeur ne manipule pas d'argent. Une extension peut fournir un reglement.
    function _pay(uint256, uint256, uint256 amount) internal virtual {
        if (amount != 0) revert PaymentsDisabled();
    }
}

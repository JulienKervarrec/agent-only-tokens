// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IAgentRegistry} from "./IAgentRegistry.sol";
import {ERC721AgentOnly} from "./ERC721AgentOnly.sol";

/// ERC-5192: Minimal Soulbound NFTs.
interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);

    function locked(uint256 tokenId) external view returns (bool);
}

/// @title Reputation badges for agents: agent-only and soulbound.
/// @notice Unaudited draft. An issuer (a repository bot, a task platform, another agent) offers a
/// badge for a piece of work; the agent claims it itself, so no badge ever arrives unsolicited.
/// Once minted, a badge never moves. Its issuer can mark it revoked; the record stays public.
/// @dev Issuing is permissionless: anyone who posts the deposit can issue, and every badge names
/// its issuer, so readers decide which issuers they trust. The deposit and the daily quota only
/// make spam costly; nobody can seize the deposit. It is refunded `exitDelay` after retiring.
contract AgentReputationBadge is ERC721AgentOnly, IERC5192 {
    struct Badge {
        address issuer;
        bytes32 category; // e.g. keccak256("code-contribution")
        bytes32 evidenceHash; // hash of the evidence document
        uint64 issuedAt; // when the agent claimed it
        bool revoked;
        string evidenceURI; // e.g. a merged pull request, a report on IPFS
    }

    struct Issuer {
        uint256 deposit;
        uint64 retiredAt; // 0 while active
        uint64 day; // day of the last offer, to count the quota
        uint32 offersToday;
    }

    uint256 public immutable issuerDeposit;
    uint32 public immutable dailyQuota;
    uint64 public immutable exitDelay;

    uint256 public lastId; // an offer and the badge it becomes share the same id
    mapping(address => Issuer) public issuers;
    mapping(uint256 => Badge) private _badges;
    mapping(uint256 => address) public offeredTo; // agent that may claim a pending offer
    mapping(address => mapping(bytes32 => bool)) public evidenceUsed; // issuer => evidence => used

    event IssuerRegistered(address indexed issuer, uint256 deposit);
    event IssuerRetired(address indexed issuer);
    event Offered(
        uint256 indexed offerId, address indexed issuer, address indexed agent, bytes32 category, bytes32 evidenceHash
    );
    event OfferCancelled(uint256 indexed offerId);
    event Claimed(uint256 indexed badgeId, address indexed agent);
    event Revoked(uint256 indexed badgeId, address indexed issuer);

    error Soulbound();
    error NotIssuer();
    error AlreadyRegistered();
    error WrongDeposit();
    error QuotaExceeded();
    error EvidenceAlreadyUsed();
    error NotYours();
    error NoSuchOffer();
    error TooEarly();

    constructor(IAgentRegistry registry_, uint256 issuerDeposit_, uint32 dailyQuota_, uint64 exitDelay_)
        ERC721("Agent Reputation Badge", "ARB")
        ERC721AgentOnly(registry_)
    {
        if (issuerDeposit_ == 0 || dailyQuota_ == 0) revert WrongDeposit();
        issuerDeposit = issuerDeposit_;
        dailyQuota = dailyQuota_;
        exitDelay = exitDelay_;
    }

    // ------------------------------------------------------------------ issuers

    function registerIssuer() external payable {
        Issuer storage i = issuers[msg.sender];
        if (i.deposit != 0 || i.retiredAt != 0) revert AlreadyRegistered();
        if (msg.value != issuerDeposit || msg.value == 0) revert WrongDeposit();
        i.deposit = msg.value;
        emit IssuerRegistered(msg.sender, msg.value);
    }

    /// Stops issuing at once. The deposit can be withdrawn `exitDelay` later.
    function retireIssuer() external {
        Issuer storage i = issuers[msg.sender];
        if (i.deposit == 0 || i.retiredAt != 0) revert NotIssuer();
        i.retiredAt = uint64(block.timestamp);
        emit IssuerRetired(msg.sender);
    }

    function withdrawDeposit() external {
        Issuer storage i = issuers[msg.sender];
        if (i.retiredAt == 0 || i.deposit == 0) revert NotIssuer();
        if (block.timestamp < i.retiredAt + exitDelay) revert TooEarly();
        uint256 amount = i.deposit;
        i.deposit = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok);
    }

    function isActiveIssuer(address account) public view returns (bool) {
        Issuer storage i = issuers[account];
        return i.deposit != 0 && i.retiredAt == 0;
    }

    // ------------------------------------------------------------------ badges

    /// An issuer offers a badge to an agent account. Nothing is minted until the agent claims it.
    function offer(address agent, bytes32 category, bytes32 evidenceHash, string calldata evidenceURI)
        external
        returns (uint256 offerId)
    {
        if (!isActiveIssuer(msg.sender)) revert NotIssuer();
        Issuer storage i = issuers[msg.sender];
        uint64 today = uint64(block.timestamp / 1 days);
        if (i.day != today) {
            i.day = today;
            i.offersToday = 0;
        }
        if (i.offersToday >= dailyQuota) revert QuotaExceeded();
        i.offersToday++;
        if (evidenceUsed[msg.sender][evidenceHash]) revert EvidenceAlreadyUsed();
        evidenceUsed[msg.sender][evidenceHash] = true;

        offerId = ++lastId;
        _badges[offerId] = Badge(msg.sender, category, evidenceHash, 0, false, evidenceURI);
        offeredTo[offerId] = agent;
        emit Offered(offerId, msg.sender, agent, category, evidenceHash);
    }

    function cancelOffer(uint256 offerId) external {
        if (offeredTo[offerId] == address(0)) revert NoSuchOffer();
        if (_badges[offerId].issuer != msg.sender) revert NotIssuer();
        delete offeredTo[offerId];
        delete _badges[offerId];
        emit OfferCancelled(offerId);
    }

    /// The agent named in the offer mints the badge to itself. The standard checks that the
    /// caller is a recognised agent and that it is the recipient.
    /// The badge keeps the offer's id.
    function claim(uint256 offerId) external returns (uint256 badgeId) {
        address agent = offeredTo[offerId];
        if (agent == address(0)) revert NoSuchOffer();
        if (agent != msg.sender) revert NotYours();
        delete offeredTo[offerId];
        badgeId = offerId;
        _badges[badgeId].issuedAt = uint64(block.timestamp);
        _mint(msg.sender, badgeId);
        emit Locked(badgeId);
        emit Claimed(badgeId, msg.sender);
    }

    /// The issuer marks one of its badges as revoked. The badge stays, flagged, for the record.
    function revoke(uint256 badgeId) external {
        _requireOwned(badgeId);
        Badge storage b = _badges[badgeId];
        if (b.issuer != msg.sender) revert NotIssuer();
        b.revoked = true;
        emit Revoked(badgeId, msg.sender);
    }

    function badge(uint256 badgeId) external view returns (Badge memory) {
        _requireOwned(badgeId);
        return _badges[badgeId];
    }

    function tokenURI(uint256 badgeId) public view override returns (string memory) {
        _requireOwned(badgeId);
        return _badges[badgeId].evidenceURI;
    }

    // ------------------------------------------------------------------ soulbound

    function locked(uint256 badgeId) external view returns (bool) {
        _requireOwned(badgeId);
        return true;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }

    /// Only minting is allowed: no transfer, no burn.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    function _approve(address, uint256, address, bool) internal pure override {
        revert Soulbound();
    }

    function _setApprovalForAll(address, address, bool) internal pure override {
        revert Soulbound();
    }
}

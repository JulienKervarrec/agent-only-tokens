// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AgentOnlyNFT, IAgentRegistry} from "./AgentOnlyNFT.sol";

interface IAgentSponsors {
    function sponsorOf(uint256 agentId) external view returns (address);
}

/// @title Extension de reglement : un coffre USDC par agent.
/// @notice Permet la vente et le pret sur gage dans la meme transaction que le changement d'etat.
/// @dev Le sponsor peut retirer des USDC. Il n'existe aucune fonction pour sortir un token.
contract AgentOnlyNFTWithVault is AgentOnlyNFT {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    mapping(uint256 => uint256) private _vault;

    event Deposited(uint256 indexed agentId, uint256 amount);
    event Withdrawn(uint256 indexed agentId, uint256 amount);

    error UnknownAgent();
    error NotSponsor();
    error InsufficientFunds();

    constructor(
        IAgentRegistry registry_,
        uint256 mintFee_,
        address feeRecipient_,
        uint32 mintQuota_,
        uint64 quotaPeriod_,
        IERC20 usdc_
    ) AgentOnlyNFT(registry_, mintFee_, feeRecipient_, mintQuota_, quotaPeriod_) {
        usdc = usdc_;
    }

    function vaultBalance(uint256 agentId) external view returns (uint256) {
        return _vault[agentId];
    }

    /// Depot ouvert a tous, pour un agent deja enrole.
    function deposit(uint256 agentId, uint256 amount) external nonReentrant {
        if (IAgentSponsors(address(registry)).sponsorOf(agentId) == address(0)) revert UnknownAgent();
        _vault[agentId] += amount;
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(agentId, amount);
    }

    function withdraw(uint256 agentId, uint256 amount) external nonReentrant {
        if (IAgentSponsors(address(registry)).sponsorOf(agentId) != msg.sender) revert NotSponsor();
        if (_vault[agentId] < amount) revert InsufficientFunds();
        _vault[agentId] -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit Withdrawn(agentId, amount);
    }

    function _pay(uint256 from, uint256 to, uint256 amount) internal override {
        if (_vault[from] < amount) revert InsufficientFunds();
        _vault[from] -= amount;
        _vault[to] += amount;
    }
}

// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Staking of agent-only NFTs for ERC-20 rewards. Unaudited draft.
/// @notice One collection, one reward token. Each staked NFT earns the same share of the reward
/// stream. The accounting follows Synthetix StakingRewards, with one NFT counted as one unit.
/// @dev The NFT is held here while staked. On the way out the token itself rejects any recipient
/// that is not an agent, so this contract cannot deliver it to a human. It must be approved as a
/// venue by the registry's attesters, like the sale and loan venues.
contract AgentStaking is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC721 public immutable nft;
    IERC20 public immutable rewardToken;
    address public immutable distributor; // may only add rewards; has no power over NFTs
    uint64 public immutable rewardsDuration;

    uint64 public periodFinish;
    uint64 public lastUpdate;
    uint256 public rewardRate; // reward units per second, for all stakes together
    uint256 public rewardPerStakeStored; // scaled by 1e18
    uint256 public totalStaked;

    mapping(uint256 => address) public stakerOf;
    mapping(address => uint256) public stakedBy;
    mapping(address => uint256) public paidPerStake;
    mapping(address => uint256) public rewards;

    event Staked(address indexed agent, uint256 indexed tokenId);
    event Unstaked(address indexed agent, uint256 indexed tokenId);
    event RewardPaid(address indexed agent, uint256 amount);
    event RewardAdded(uint256 amount, uint64 periodFinish);

    error NotOwner();
    error NotStaker();
    error NotDistributor();
    error RateTooLow();

    constructor(IERC721 nft_, IERC20 rewardToken_, address distributor_, uint64 rewardsDuration_) {
        nft = nft_;
        rewardToken = rewardToken_;
        distributor = distributor_;
        rewardsDuration = rewardsDuration_;
    }

    // ------------------------------------------------------------------ views

    function lastTimeRewardApplicable() public view returns (uint64) {
        return block.timestamp < periodFinish ? uint64(block.timestamp) : periodFinish;
    }

    function rewardPerStake() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerStakeStored;
        return rewardPerStakeStored + (lastTimeRewardApplicable() - lastUpdate) * rewardRate * 1e18 / totalStaked;
    }

    function earned(address agent) public view returns (uint256) {
        return rewards[agent] + stakedBy[agent] * (rewardPerStake() - paidPerStake[agent]) / 1e18;
    }

    modifier updateReward(address agent) {
        rewardPerStakeStored = rewardPerStake();
        lastUpdate = lastTimeRewardApplicable();
        if (agent != address(0)) {
            rewards[agent] = earned(agent);
            paidPerStake[agent] = rewardPerStakeStored;
        }
        _;
    }

    // ------------------------------------------------------------------ stakers

    /// The holder stakes its NFT. It must have approved this contract first.
    function stake(uint256 tokenId) external nonReentrant updateReward(msg.sender) {
        if (nft.ownerOf(tokenId) != msg.sender) revert NotOwner();
        stakerOf[tokenId] = msg.sender;
        stakedBy[msg.sender]++;
        totalStaked++;
        nft.transferFrom(msg.sender, address(this), tokenId);
        emit Staked(msg.sender, tokenId);
    }

    /// Only the agent that staked the NFT gets it back, together with its rewards.
    function unstake(uint256 tokenId) external nonReentrant updateReward(msg.sender) {
        if (stakerOf[tokenId] != msg.sender) revert NotStaker();
        delete stakerOf[tokenId];
        stakedBy[msg.sender]--;
        totalStaked--;
        nft.transferFrom(address(this), msg.sender, tokenId);
        emit Unstaked(msg.sender, tokenId);
        _payReward();
    }

    function getReward() external nonReentrant updateReward(msg.sender) {
        _payReward();
    }

    function _payReward() private {
        uint256 amount = rewards[msg.sender];
        if (amount == 0) return;
        rewards[msg.sender] = 0;
        rewardToken.safeTransfer(msg.sender, amount);
        emit RewardPaid(msg.sender, amount);
    }

    // ------------------------------------------------------------------ distributor

    /// Adds `amount` to the stream and spreads what is left over `rewardsDuration` from now.
    /// Only the distributor can call it, so nobody can stretch the stream to slow it down.
    function notifyRewardAmount(uint256 amount) external nonReentrant updateReward(address(0)) {
        if (msg.sender != distributor) revert NotDistributor();
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 leftover = block.timestamp < periodFinish ? (periodFinish - block.timestamp) * rewardRate : 0;
        rewardRate = (amount + leftover) / rewardsDuration;
        if (rewardRate == 0) revert RateTooLow();
        lastUpdate = uint64(block.timestamp);
        periodFinish = uint64(block.timestamp) + rewardsDuration;
        emit RewardAdded(amount, periodFinish);
    }
}

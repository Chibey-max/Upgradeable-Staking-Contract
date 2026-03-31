// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibStaking} from "../libraries/LibStaking.sol";
import {IERC20, IRewardToken, IReceiptToken} from "../interfaces/ITokens.sol";

// ─────────────────────────────────────────────────────────────────────────────
// StakingFacet
// Core user-facing staking actions: stake, withdraw, emergencyWithdraw,
// claimRewards. All state is read/written through LibStaking storage.
// ─────────────────────────────────────────────────────────────────────────────

contract StakingFacet {
    event Staked(address indexed user, uint256 indexed poolId, uint256 stakeId, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed poolId, uint256 stakeId, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 indexed poolId, uint256 stakeId, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed poolId, uint256 stakeId, uint256 amount);

    function stake(uint256 poolId, uint256 amount) external {
        LibStaking.StakingStorage storage ss = LibStaking.stakingStorage();

        require(amount > 0, "Must Stake Token greater than Zero");
        require(poolId < ss.poolCount, "Pool does not exist");

        uint256 stakeId = ss.stakeCount[poolId][msg.sender];

        ss.userStakes[poolId][msg.sender][stakeId] = LibStaking.Stake({
            amount: amount,
            startTime: block.timestamp,
            unlockTime: block.timestamp + ss.poolsLockDuration[poolId],
            rewardRate: ss.poolsRewardRate[poolId],
            lastUpdateTime: block.timestamp,
            rewardAccrued: 0,
            active: true
        });

        bool success = IERC20(ss.stakeToken).transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer Failed");

        ss.poolTotalStaked[poolId] += amount;
        IReceiptToken(ss.receiptToken).mint(msg.sender, amount);
        ss.stakeCount[poolId][msg.sender]++;

        emit Staked(msg.sender, poolId, stakeId, amount);
    }

    function withdraw(uint256 poolId, uint256 stakeId) external {
        LibStaking.StakingStorage storage ss = LibStaking.stakingStorage();
        LibStaking.Stake storage s = ss.userStakes[poolId][msg.sender][stakeId];

        require(s.active, "Stake not active");
        require(block.timestamp >= s.unlockTime, "Pool still locked");

        uint256 totalReward = s.rewardAccrued + LibStaking.calculateReward(poolId, msg.sender, stakeId);
        uint256 stakedAmount = s.amount;

        s.active = false;
        ss.poolTotalStaked[poolId] -= stakedAmount;

        IReceiptToken(ss.receiptToken).burn(msg.sender, stakedAmount);

        bool success1 = IERC20(ss.stakeToken).transfer(msg.sender, stakedAmount);
        require(success1, "Stake transfer failed");

        if (totalReward > 0) {
            bool success2 = IRewardToken(ss.rewardToken).mint(msg.sender, totalReward);
            require(success2, "Reward mint failed");
        }

        emit Withdrawn(msg.sender, poolId, stakeId, stakedAmount);
    }

    function claimRewards(uint256 poolId, uint256 stakeId) external {
        LibStaking.StakingStorage storage ss = LibStaking.stakingStorage();
        LibStaking.Stake storage s = ss.userStakes[poolId][msg.sender][stakeId];

        require(s.active, "Stake not active");

        uint256 rewards = s.rewardAccrued + LibStaking.calculateReward(poolId, msg.sender, stakeId);
        require(rewards > 0, "No rewards to claim");

        s.rewardAccrued = 0;
        s.lastUpdateTime = block.timestamp;

        bool success = IRewardToken(ss.rewardToken).mint(msg.sender, rewards);
        require(success, "Reward mint failed");

        emit RewardsClaimed(msg.sender, poolId, stakeId, rewards);
    }

    function emergencyWithdraw(uint256 poolId, uint256 stakeId) external {
        LibStaking.StakingStorage storage ss = LibStaking.stakingStorage();
        LibStaking.Stake storage s = ss.userStakes[poolId][msg.sender][stakeId];

        require(s.active, "Stake not active");
        require(s.amount > 0, "Nothing staked");

        uint256 amount = s.amount;
        uint256 penalty = amount * 10 / 100;
        uint256 amountAfterPenalty = amount - penalty;

        s.active = false;
        s.rewardAccrued = 0;
        ss.poolTotalStaked[poolId] -= amount;

        IReceiptToken(ss.receiptToken).burn(msg.sender, amount);

        bool success1 = IERC20(ss.stakeToken).transfer(msg.sender, amountAfterPenalty);
        require(success1, "Transfer failed");

        bool success2 = IERC20(ss.stakeToken).transfer(ss.owner, penalty);
        require(success2, "Penalty transfer failed");

        emit EmergencyWithdraw(msg.sender, poolId, stakeId, amount);
    }
}

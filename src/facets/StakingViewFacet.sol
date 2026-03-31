// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibStaking} from "../libraries/LibStaking.sol";

// ─────────────────────────────────────────────────────────────────────────────
// StakingViewFacet  (V1)
// Pure read-only queries. Separated from StakingFacet so it can be upgraded
// independently via a diamondCut Replace without touching write logic.
// ─────────────────────────────────────────────────────────────────────────────

contract StakingViewFacet {
    function getPoolTotalStaked(uint256 poolId) external view returns (uint256) {
        return LibStaking.stakingStorage().poolTotalStaked[poolId];
    }

    function getPendingReward(uint256 poolId, uint256 stakeId) external view returns (uint256) {
        LibStaking.StakingStorage storage ss = LibStaking.stakingStorage();
        LibStaking.Stake storage s = ss.userStakes[poolId][msg.sender][stakeId];
        return s.rewardAccrued + LibStaking.calculateReward(poolId, msg.sender, stakeId);
    }

    function getStake(uint256 poolId, uint256 stakeId) external view returns (LibStaking.Stake memory) {
        return LibStaking.stakingStorage().userStakes[poolId][msg.sender][stakeId];
    }

    function getStakeCount(uint256 poolId, address user) external view returns (uint256) {
        return LibStaking.stakingStorage().stakeCount[poolId][user];
    }

    function getPoolRewardRate(uint256 poolId) external view returns (uint256) {
        return LibStaking.stakingStorage().poolsRewardRate[poolId];
    }

    function getPoolLockDuration(uint256 poolId) external view returns (uint256) {
        return LibStaking.stakingStorage().poolsLockDuration[poolId];
    }

    function getPoolCount() external view returns (uint256) {
        return LibStaking.stakingStorage().poolCount;
    }
}

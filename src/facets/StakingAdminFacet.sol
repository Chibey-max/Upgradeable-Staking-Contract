// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LibStaking } from "../libraries/LibStaking.sol";

// ─────────────────────────────────────────────────────────────────────────────
// StakingAdminFacet
// Owner-only functions. Isolated in its own facet so it can be Removed via
// diamondCut to permanently lock protocol parameters if desired.
// ─────────────────────────────────────────────────────────────────────────────

contract StakingAdminFacet {

    event RewardRateUpdated(uint256 indexed poolId, uint256 newRate);
    event PoolCreated(uint256 indexed poolId, uint256 lockDuration, uint256 rewardRate);

    function updateRewardRate(uint256 poolId, uint256 newRate) external {
        LibStaking.enforceIsOwner();
        LibStaking.StakingStorage storage ss = LibStaking.stakingStorage();
        require(poolId < ss.poolCount, "Pool does not exist");
        ss.poolsRewardRate[poolId] = newRate;
        emit RewardRateUpdated(poolId, newRate);
    }

    function createPool(uint256 lockDuration, uint256 rewardRate) external {
        LibStaking.enforceIsOwner();
        LibStaking.StakingStorage storage ss = LibStaking.stakingStorage();
        uint256 poolId = ss.poolCount;
        ss.poolsRewardRate[poolId]    = rewardRate;
        ss.poolsLockDuration[poolId]  = lockDuration;
        ss.poolCount++;
        emit PoolCreated(poolId, lockDuration, rewardRate);
    }
}

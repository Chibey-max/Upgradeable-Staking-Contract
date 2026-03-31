// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibStaking} from "../libraries/LibStaking.sol";

// ─────────────────────────────────────────────────────────────────────────────
// StakingViewFacetV2
// Drop-in upgrade for StakingViewFacet. Demonstrates the Diamond Replace cut:
// the same selectors (getPoolTotalStaked, getPendingReward) are re-routed to
// this contract without touching StakingFacet or StakingAdminFacet.
//
// V2 changes: getPendingReward now returns 0 when the stake is no longer
// active (prevents confusing "phantom reward" reads after withdrawal).
// ─────────────────────────────────────────────────────────────────────────────

contract StakingViewFacetV2 {
    /// @notice V2 — returns 0 for inactive stakes instead of stale accrued value
    function getPendingReward(uint256 poolId, uint256 stakeId) external view returns (uint256) {
        LibStaking.StakingStorage storage ss = LibStaking.stakingStorage();
        LibStaking.Stake storage s = ss.userStakes[poolId][msg.sender][stakeId];
        if (!s.active) return 0;
        return s.rewardAccrued + LibStaking.calculateReward(poolId, msg.sender, stakeId);
    }

    /// @notice Same as V1 — unchanged
    function getPoolTotalStaked(uint256 poolId) external view returns (uint256) {
        return LibStaking.stakingStorage().poolTotalStaked[poolId];
    }

    /// @notice V2 bonus: returns the version string so tests can prove the upgrade landed
    function version() external pure returns (string memory) {
        return "StakingViewFacet-V2";
    }
}

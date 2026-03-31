// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibStaking} from "./libraries/LibStaking.sol";

// ─────────────────────────────────────────────────────────────────────────────
// DiamondInit
// Delegatecalled by the Diamond during the first diamondCut that attaches
// staking facets. Seeds LibStaking storage with token addresses, owner, and
// the four default pools (matching the original DefiStaking constructor).
//
// Usage in diamondCut call:
//   _init     = address(diamondInit)
//   _calldata = abi.encodeCall(DiamondInit.init, (stakeToken, rewardToken, receiptToken))
// ─────────────────────────────────────────────────────────────────────────────

contract DiamondInit {
    function init(address stakeToken, address rewardToken, address receiptToken) external {
        LibStaking.StakingStorage storage ss = LibStaking.stakingStorage();

        require(ss.poolCount == 0, "DiamondInit: already initialized");

        ss.stakeToken = stakeToken;
        ss.rewardToken = rewardToken;
        ss.receiptToken = receiptToken;
        ss.owner = msg.sender; // msg.sender is the Diamond (via delegatecall)

        // Mirror the four pools from the original DefiStaking constructor
        _createPool(ss, 300, 3170979198); // 5 min
        _createPool(ss, 600, 7927447995); // 10 min
        _createPool(ss, 3600, 15854895991); // 1 hour
        _createPool(ss, 86400, 31709791983); // 1 day
    }

    function _createPool(LibStaking.StakingStorage storage ss, uint256 lockDuration, uint256 rewardRate) private {
        uint256 poolId = ss.poolCount;
        ss.poolsRewardRate[poolId] = rewardRate;
        ss.poolsLockDuration[poolId] = lockDuration;
        ss.poolCount++;
    }
}

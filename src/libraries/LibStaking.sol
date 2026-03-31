// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ─────────────────────────────────────────────────────────────────────────────
// LibStaking
// All staking state lives here in a dedicated Diamond storage slot.
// Every staking facet reads/writes this single struct — no clashes with
// LibDiamond or any other facet's storage.
// ─────────────────────────────────────────────────────────────────────────────

library LibStaking {

    bytes32 constant STAKING_STORAGE_POSITION = keccak256("diamond.storage.staking");

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 unlockTime;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardAccrued;
        bool    active;
    }

    struct StakingStorage {
        // Token addresses
        address stakeToken;
        address rewardToken;
        address receiptToken;

        // Pool metadata
        uint256 poolCount;
        mapping(uint256 poolId => uint256)          poolTotalStaked;
        mapping(uint256 poolId => uint256)          poolsRewardRate;
        mapping(uint256 poolId => uint256)          poolsLockDuration;

        // Per-user stake records
        mapping(uint256 poolId => mapping(address user => mapping(uint256 stakeId => Stake))) userStakes;
        mapping(uint256 poolId => mapping(address user => uint256))                           stakeCount;

        // Admin
        address owner;
    }

    function stakingStorage() internal pure returns (StakingStorage storage ss) {
        bytes32 position = STAKING_STORAGE_POSITION;
        assembly {
            ss.slot := position
        }
    }

    // ── Reward math ────────────────────────────────────────────────────────

    function calculateReward(
        uint256 poolId,
        address user,
        uint256 stakeId
    ) internal view returns (uint256) {
        Stake storage s = stakingStorage().userStakes[poolId][user][stakeId];
        if (s.amount == 0) return 0;
        uint256 timeElapsed = block.timestamp - s.lastUpdateTime;
        return s.amount * s.rewardRate * timeElapsed / 1e18;
    }

    // ── Access control ─────────────────────────────────────────────────────

    function enforceIsOwner() internal view {
        require(msg.sender == stakingStorage().owner, "unauthorized access");
    }
}

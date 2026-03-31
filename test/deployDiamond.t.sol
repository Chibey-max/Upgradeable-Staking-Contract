// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { Diamond }            from "../src/Diamond.sol";
import { DiamondCutFacet }    from "../src/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet }  from "../src/facets/DiamondLoupeFacet.sol";
import { DiamondInit }        from "../src/DiamondInit.sol";

import { StakingFacet }       from "../src/facets/StakingFacet.sol";
import { StakingViewFacet }   from "../src/facets/StakingViewFacet.sol";
import { StakingViewFacetV2 } from "../src/facets/StakingViewFacetV2.sol";
import { StakingAdminFacet }  from "../src/facets/StakingAdminFacet.sol";

import { MockERC20 }          from "../src/tokens/MockERC20.sol";

import { IDiamondCut }        from "../src/interfaces/IDiamondCut.sol";
import { IDiamondLoupe }      from "../src/interfaces/IDiamondLoupe.sol";
import { LibStaking }         from "../src/libraries/LibStaking.sol";

// ── Thin interfaces for calling the Diamond proxy ──────────────────────────

interface IStakingFacet {
    function stake(uint256 poolId, uint256 amount) external;
    function withdraw(uint256 poolId, uint256 stakeId) external;
    function emergencyWithdraw(uint256 poolId, uint256 stakeId) external;
    function claimRewards(uint256 poolId, uint256 stakeId) external;
}

interface IStakingViewFacet {
    function getPoolTotalStaked(uint256 poolId) external view returns (uint256);
    function getPendingReward(uint256 poolId, uint256 stakeId) external view returns (uint256);
    function getPoolCount() external view returns (uint256);
    function getPoolRewardRate(uint256 poolId) external view returns (uint256);
}

interface IStakingViewFacetV2 {
    function getPoolTotalStaked(uint256 poolId) external view returns (uint256);
    function getPendingReward(uint256 poolId, uint256 stakeId) external view returns (uint256);
    function version() external pure returns (string memory);
}

interface IStakingAdminFacet {
    function updateRewardRate(uint256 poolId, uint256 newRate) external;
    function createPool(uint256 lockDuration, uint256 rewardRate) external;
}

// ─────────────────────────────────────────────────────────────────────────────

contract DeployDiamondTest is Test {

    // ── Deployed contracts ─────────────────────────────────────────────────
    Diamond            diamond;
    DiamondCutFacet    cutFacet;
    DiamondLoupeFacet  loupeFacet;
    DiamondInit        diamondInit;

    StakingFacet       stakingFacet;
    StakingViewFacet   viewFacet;
    StakingViewFacetV2 viewFacetV2;
    StakingAdminFacet  adminFacet;

    MockERC20 stakeToken;
    MockERC20 rewardToken;
    MockERC20 receiptToken;

    // ── Actors ─────────────────────────────────────────────────────────────
    address owner  = address(this);
    address user1;
    address user2;

    // ── Constants ──────────────────────────────────────────────────────────
    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 constant USER_BALANCE   = 10_000e18;
    uint256 constant STAKE_AMOUNT   = 100e18;
    uint256 constant POOL_0         = 0; // 300-second lock
    uint256 constant POOL_0_LOCK    = 300;

    // ─────────────────────────────────────────────────────────────────────
    // setUp
    // ─────────────────────────────────────────────────────────────────────

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // ── 1. Tokens ──────────────────────────────────────────────────────
        stakeToken   = new MockERC20("Stake Token",   "STK", 18, INITIAL_SUPPLY);
        rewardToken  = new MockERC20("Reward Token",  "RWD", 18, 0);
        receiptToken = new MockERC20("Receipt Token", "RCT", 18, 0);

        // ── 2. Diamond core ────────────────────────────────────────────────
        cutFacet   = new DiamondCutFacet();
        loupeFacet = new DiamondLoupeFacet();
        diamondInit = new DiamondInit();

        // Diamond registers DiamondCutFacet in its constructor
        diamond = new Diamond(owner, address(cutFacet));

        // ── 3. Staking facets ──────────────────────────────────────────────
        stakingFacet = new StakingFacet();
        viewFacet    = new StakingViewFacet();
        viewFacetV2  = new StakingViewFacetV2();
        adminFacet   = new StakingAdminFacet();

        // ── 4. Grant Diamond minter rights on reward + receipt tokens ───────
        rewardToken.addMinter(address(diamond));
        receiptToken.addMinter(address(diamond));

        // ── 5. Fund users ──────────────────────────────────────────────────
        stakeToken.transfer(user1, USER_BALANCE);
        stakeToken.transfer(user2, USER_BALANCE);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Selector helpers
    // ─────────────────────────────────────────────────────────────────────

    function _loupeSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = IDiamondLoupe.facets.selector;
        s[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        s[2] = IDiamondLoupe.facetAddresses.selector;
        s[3] = IDiamondLoupe.facetAddress.selector;
    }

    function _stakingSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = IStakingFacet.stake.selector;
        s[1] = IStakingFacet.withdraw.selector;
        s[2] = IStakingFacet.emergencyWithdraw.selector;
        s[3] = IStakingFacet.claimRewards.selector;
    }

    function _viewSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = IStakingViewFacet.getPoolTotalStaked.selector;
        s[1] = IStakingViewFacet.getPendingReward.selector;
    }

    function _adminSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = IStakingAdminFacet.updateRewardRate.selector;
        s[1] = IStakingAdminFacet.createPool.selector;
    }

    // ── Build a single-item FacetCut array ─────────────────────────────────
    function _cut(
        address facet,
        IDiamondCut.FacetCutAction action,
        bytes4[] memory selectors
    ) internal pure returns (IDiamondCut.FacetCut[] memory cuts) {
        cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({ facetAddress: facet, action: action, functionSelectors: selectors });
    }

    // ─────────────────────────────────────────────────────────────────────
    // Full initialisation helper used by integration tests
    // Registers loupe + all three staking facets and runs DiamondInit
    // ─────────────────────────────────────────────────────────────────────

    function _fullInit() internal {
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](4);
        cuts[0] = IDiamondCut.FacetCut({ facetAddress: address(loupeFacet),   action: IDiamondCut.FacetCutAction.Add, functionSelectors: _loupeSelectors()    });
        cuts[1] = IDiamondCut.FacetCut({ facetAddress: address(stakingFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: _stakingSelectors() });
        cuts[2] = IDiamondCut.FacetCut({ facetAddress: address(viewFacet),    action: IDiamondCut.FacetCutAction.Add, functionSelectors: _viewSelectors()    });
        cuts[3] = IDiamondCut.FacetCut({ facetAddress: address(adminFacet),   action: IDiamondCut.FacetCutAction.Add, functionSelectors: _adminSelectors()   });

        IDiamondCut(address(diamond)).diamondCut(
            cuts,
            address(diamondInit),
            abi.encodeCall(DiamondInit.init, (address(stakeToken), address(rewardToken), address(receiptToken)))
        );
    }

    // ═════════════════════════════════════════════════════════════════════
    // ADD
    // ═════════════════════════════════════════════════════════════════════

    function test_Add_LoupeFacet() public {
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(loupeFacet), IDiamondCut.FacetCutAction.Add, _loupeSelectors()),
            address(0), ""
        );

        // CutFacet (from constructor) + LoupeFacet = 2
        address[] memory addrs = IDiamondLoupe(address(diamond)).facetAddresses();
        assertEq(addrs.length, 2, "Should have 2 facets");
    }

    function test_Add_AllStakingFacets() public {
        _fullInit();

        // CutFacet + LoupeFacet + StakingFacet + ViewFacet + AdminFacet = 5
        address[] memory addrs = IDiamondLoupe(address(diamond)).facetAddresses();
        assertEq(addrs.length, 5, "Expected 5 facets after full init");
    }

    function test_Add_SelectorsRoutedCorrectly() public {
        _fullInit();

        assertEq(IDiamondLoupe(address(diamond)).facetAddress(IStakingFacet.stake.selector),                 address(stakingFacet), "stake() wrong facet");
        assertEq(IDiamondLoupe(address(diamond)).facetAddress(IStakingViewFacet.getPoolTotalStaked.selector), address(viewFacet),    "getPoolTotalStaked() wrong facet");
        assertEq(IDiamondLoupe(address(diamond)).facetAddress(IStakingAdminFacet.updateRewardRate.selector),  address(adminFacet),   "updateRewardRate() wrong facet");
    }

    function test_Add_DiamondInitSeedsStorage() public {
        _fullInit();
        // DiamondInit creates 4 pools
        assertEq(IStakingViewFacet(address(diamond)).getPoolCount(), 4, "Should have 4 pools after init");
    }

    function test_Add_RevertWhen_DuplicateSelector() public {
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(stakingFacet), IDiamondCut.FacetCutAction.Add, _stakingSelectors()),
            address(0), ""
        );
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(stakingFacet), IDiamondCut.FacetCutAction.Add, _stakingSelectors()),
            address(0), ""
        );
    }

    function test_Add_RevertWhen_NonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(stakingFacet), IDiamondCut.FacetCutAction.Add, _stakingSelectors()),
            address(0), ""
        );
    }

    function test_Add_RevertWhen_ZeroAddressFacet() public {
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(0), IDiamondCut.FacetCutAction.Add, _stakingSelectors()),
            address(0), ""
        );
    }

    // ═════════════════════════════════════════════════════════════════════
    // REPLACE
    // Swap StakingViewFacet → StakingViewFacetV2
    // ═════════════════════════════════════════════════════════════════════

    function test_Replace_ViewFacetWithV2() public {
        _fullInit();

        // Confirm V1 is routing
        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(IStakingViewFacet.getPendingReward.selector),
            address(viewFacet),
            "Pre-replace: should point to V1"
        );

        // Replace with V2
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(viewFacetV2), IDiamondCut.FacetCutAction.Replace, _viewSelectors()),
            address(0), ""
        );

        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(IStakingViewFacet.getPendingReward.selector),
            address(viewFacetV2),
            "Post-replace: should point to V2"
        );
        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(IStakingViewFacet.getPoolTotalStaked.selector),
            address(viewFacetV2),
            "Post-replace: getPoolTotalStaked should point to V2"
        );
    }

    function test_Replace_FacetCountUnchanged() public {
        _fullInit();
        uint256 before = IDiamondLoupe(address(diamond)).facetAddresses().length;

        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(viewFacetV2), IDiamondCut.FacetCutAction.Replace, _viewSelectors()),
            address(0), ""
        );

        assertEq(IDiamondLoupe(address(diamond)).facetAddresses().length, before, "Replace must not change facet count");
    }

    function test_Replace_V2VersionFunctionCallable() public {
        _fullInit();

        // Attach the extra version() selector that only V2 exposes
        bytes4[] memory extraSelectors = new bytes4[](1);
        extraSelectors[0] = IStakingViewFacetV2.version.selector;
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(viewFacetV2), IDiamondCut.FacetCutAction.Add, extraSelectors),
            address(0), ""
        );

        // Now replace the shared selectors
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(viewFacetV2), IDiamondCut.FacetCutAction.Replace, _viewSelectors()),
            address(0), ""
        );

        string memory ver = IStakingViewFacetV2(address(diamond)).version();
        assertEq(ver, "StakingViewFacet-V2", "Version string mismatch");
    }

    function test_Replace_RevertWhen_SameFacetAddress() public {
        _fullInit();
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(viewFacet), IDiamondCut.FacetCutAction.Replace, _viewSelectors()),
            address(0), ""
        );
    }

    function test_Replace_RevertWhen_SelectorNeverAdded() public {
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(viewFacetV2), IDiamondCut.FacetCutAction.Replace, _viewSelectors()),
            address(0), ""
        );
    }

    // ═════════════════════════════════════════════════════════════════════
    // REMOVE
    // Strip StakingAdminFacet — permanently locks reward rates
    // ═════════════════════════════════════════════════════════════════════

    function test_Remove_AdminFacet() public {
        _fullInit();

        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(IStakingAdminFacet.updateRewardRate.selector),
            address(adminFacet),
            "Pre-remove: admin facet should be routed"
        );

        // For Remove, facetAddress must be address(0) per EIP-2535
        IDiamondCut.FacetCut[] memory removeCut = new IDiamondCut.FacetCut[](1);
        removeCut[0] = IDiamondCut.FacetCut({
            facetAddress:      address(0),
            action:            IDiamondCut.FacetCutAction.Remove,
            functionSelectors: _adminSelectors()
        });
        IDiamondCut(address(diamond)).diamondCut(removeCut, address(0), "");

        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(IStakingAdminFacet.updateRewardRate.selector),
            address(0),
            "Post-remove: updateRewardRate should be unrouted"
        );
    }

    function test_Remove_CallRevertsAfterRemoval() public {
        _fullInit();

        IDiamondCut.FacetCut[] memory removeCut = new IDiamondCut.FacetCut[](1);
        removeCut[0] = IDiamondCut.FacetCut({
            facetAddress:      address(0),
            action:            IDiamondCut.FacetCutAction.Remove,
            functionSelectors: _adminSelectors()
        });
        IDiamondCut(address(diamond)).diamondCut(removeCut, address(0), "");

        vm.expectRevert();
        IStakingAdminFacet(address(diamond)).updateRewardRate(POOL_0, 999);
    }

    function test_Remove_DecreasesFacetCount() public {
        _fullInit();
        uint256 before = IDiamondLoupe(address(diamond)).facetAddresses().length;

        IDiamondCut.FacetCut[] memory removeCut = new IDiamondCut.FacetCut[](1);
        removeCut[0] = IDiamondCut.FacetCut({
            facetAddress:      address(0),
            action:            IDiamondCut.FacetCutAction.Remove,
            functionSelectors: _adminSelectors()
        });
        IDiamondCut(address(diamond)).diamondCut(removeCut, address(0), "");

        assertEq(IDiamondLoupe(address(diamond)).facetAddresses().length, before - 1, "Facet count should drop by 1");
    }

    function test_Remove_RevertWhen_SelectorNeverAdded() public {
        IDiamondCut.FacetCut[] memory removeCut = new IDiamondCut.FacetCut[](1);
        removeCut[0] = IDiamondCut.FacetCut({
            facetAddress:      address(0),
            action:            IDiamondCut.FacetCutAction.Remove,
            functionSelectors: _adminSelectors()
        });
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(removeCut, address(0), "");
    }

    function test_Remove_RevertWhen_FacetAddressNotZero() public {
        _fullInit();
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(adminFacet), IDiamondCut.FacetCutAction.Remove, _adminSelectors()),
            address(0), ""
        );
    }

    // ═════════════════════════════════════════════════════════════════════
    // Integration — full staking flows through the Diamond proxy
    // ═════════════════════════════════════════════════════════════════════

    function test_Integration_StakeUpdatesPool() public {
        _fullInit();

        vm.startPrank(user1);
        stakeToken.approve(address(diamond), STAKE_AMOUNT);
        IStakingFacet(address(diamond)).stake(POOL_0, STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(IStakingViewFacet(address(diamond)).getPoolTotalStaked(POOL_0), STAKE_AMOUNT);
    }

    function test_Integration_WithdrawAfterLock() public {
        _fullInit();

        vm.startPrank(user1);
        stakeToken.approve(address(diamond), STAKE_AMOUNT);
        IStakingFacet(address(diamond)).stake(POOL_0, STAKE_AMOUNT);
        vm.stopPrank();

        skip(POOL_0_LOCK + 1);

        uint256 balBefore = stakeToken.balanceOf(user1);
        vm.prank(user1);
        IStakingFacet(address(diamond)).withdraw(POOL_0, 0);

        assertEq(stakeToken.balanceOf(user1) - balBefore, STAKE_AMOUNT, "Should receive full stake back");
        assertEq(IStakingViewFacet(address(diamond)).getPoolTotalStaked(POOL_0), 0, "Pool should be empty");
    }

    function test_Integration_WithdrawBeforeLock_Reverts() public {
        _fullInit();

        vm.startPrank(user1);
        stakeToken.approve(address(diamond), STAKE_AMOUNT);
        IStakingFacet(address(diamond)).stake(POOL_0, STAKE_AMOUNT);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(bytes("Pool still locked"));
        IStakingFacet(address(diamond)).withdraw(POOL_0, 0);
    }

    function test_Integration_EmergencyWithdraw_AppliesTenPercentPenalty() public {
        _fullInit();

        vm.startPrank(user1);
        stakeToken.approve(address(diamond), STAKE_AMOUNT);
        IStakingFacet(address(diamond)).stake(POOL_0, STAKE_AMOUNT);
        vm.stopPrank();

        uint256 balBefore = stakeToken.balanceOf(user1);
        vm.prank(user1);
        IStakingFacet(address(diamond)).emergencyWithdraw(POOL_0, 0);

        assertEq(stakeToken.balanceOf(user1) - balBefore, STAKE_AMOUNT * 90 / 100, "Penalty should be 10%");
    }

    function test_Integration_RewardsAccrue() public {
        _fullInit();

        vm.startPrank(user1);
        stakeToken.approve(address(diamond), STAKE_AMOUNT);
        IStakingFacet(address(diamond)).stake(POOL_0, STAKE_AMOUNT);
        vm.stopPrank();

        skip(100);

        uint256 pending = IStakingViewFacet(address(diamond)).getPendingReward(POOL_0, 0);
        // user1 calling getPendingReward — uses msg.sender
        vm.prank(user1);
        pending = IStakingViewFacet(address(diamond)).getPendingReward(POOL_0, 0);
        assertGt(pending, 0, "Rewards should have accrued");
    }

    function test_Integration_ClaimRewardsMintTokens() public {
        _fullInit();

        vm.startPrank(user1);
        stakeToken.approve(address(diamond), STAKE_AMOUNT);
        IStakingFacet(address(diamond)).stake(POOL_0, STAKE_AMOUNT);
        vm.stopPrank();

        skip(100);

        uint256 rwdBefore = rewardToken.balanceOf(user1);
        vm.prank(user1);
        IStakingFacet(address(diamond)).claimRewards(POOL_0, 0);

        assertGt(rewardToken.balanceOf(user1), rwdBefore, "Reward token balance should increase");
    }

    function test_Integration_AdminUpdateRewardRate() public {
        _fullInit();
        uint256 newRate = 5e18;
        IStakingAdminFacet(address(diamond)).updateRewardRate(POOL_0, newRate);
        assertEq(IStakingViewFacet(address(diamond)).getPoolRewardRate(POOL_0), newRate);
    }

    function test_Integration_AdminUpdateRewardRate_RevertNonOwner() public {
        _fullInit();
        vm.prank(user1);
        vm.expectRevert(bytes("unauthorized access"));
        IStakingAdminFacet(address(diamond)).updateRewardRate(POOL_0, 5e18);
    }

    function test_Integration_MultipleUsersMultiplePools() public {
        _fullInit();

        // user1 stakes in pool 0, user2 stakes in pool 1
        vm.startPrank(user1);
        stakeToken.approve(address(diamond), STAKE_AMOUNT);
        IStakingFacet(address(diamond)).stake(0, STAKE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user2);
        stakeToken.approve(address(diamond), STAKE_AMOUNT);
        IStakingFacet(address(diamond)).stake(1, STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(IStakingViewFacet(address(diamond)).getPoolTotalStaked(0), STAKE_AMOUNT);
        assertEq(IStakingViewFacet(address(diamond)).getPoolTotalStaked(1), STAKE_AMOUNT);
    }

    function test_Integration_ReplaceViewFacet_PreservesState() public {
        _fullInit();

        // Stake before the upgrade
        vm.startPrank(user1);
        stakeToken.approve(address(diamond), STAKE_AMOUNT);
        IStakingFacet(address(diamond)).stake(POOL_0, STAKE_AMOUNT);
        vm.stopPrank();

        // Upgrade view facet
        IDiamondCut(address(diamond)).diamondCut(
            _cut(address(viewFacetV2), IDiamondCut.FacetCutAction.Replace, _viewSelectors()),
            address(0), ""
        );

        // State should still be there after the upgrade
        assertEq(IStakingViewFacetV2(address(diamond)).getPoolTotalStaked(POOL_0), STAKE_AMOUNT, "State lost after Replace");
    }

    function test_Integration_RemoveAdmin_ThenStakingStillWorks() public {
        _fullInit();

        // Remove admin facet
        IDiamondCut.FacetCut[] memory removeCut = new IDiamondCut.FacetCut[](1);
        removeCut[0] = IDiamondCut.FacetCut({
            facetAddress:      address(0),
            action:            IDiamondCut.FacetCutAction.Remove,
            functionSelectors: _adminSelectors()
        });
        IDiamondCut(address(diamond)).diamondCut(removeCut, address(0), "");

        // Core staking should still work
        vm.startPrank(user1);
        stakeToken.approve(address(diamond), STAKE_AMOUNT);
        IStakingFacet(address(diamond)).stake(POOL_0, STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(IStakingViewFacet(address(diamond)).getPoolTotalStaked(POOL_0), STAKE_AMOUNT);
    }
}

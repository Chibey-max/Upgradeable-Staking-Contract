// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import "../src/interfaces/IDiamondCut.sol";
import "../src/Diamond.sol";

import "../src/facets/DiamondCutFacet.sol";
import "../src/facets/DiamondLoupeFacet.sol";

import "../src/facets/StakingFacet.sol";
import "../src/facets/StakingViewFacet.sol";
import "../src/facets/StakingAdminFacet.sol";

import "../src/DiamondInit.sol";
import "../src/tokens/MockERC20.sol";

contract DiamondDeployer is Test, IDiamondCut {
    // ── Core ─────────────────────────────────────
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet loupe;

    // ── Staking Facets ───────────────────────────
    StakingFacet staking;
    StakingViewFacet viewFacet;
    StakingAdminFacet admin;

    DiamondInit init;

    // ── Tokens ───────────────────────────────────
    MockERC20 stakeToken;
    MockERC20 rewardToken;
    MockERC20 receiptToken;

    address user;

    function setUp() public {
        user = makeAddr("user");

        // ── Deploy core ──────────────────────────
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet));

        loupe = new DiamondLoupeFacet();

        // ── Deploy staking facets ────────────────
        staking = new StakingFacet();
        viewFacet = new StakingViewFacet();
        admin = new StakingAdminFacet();

        init = new DiamondInit();

        // ── Deploy tokens ────────────────────────
        stakeToken = new MockERC20("Stake Token", "STK", 18, 1_000_000e18);
        rewardToken = new MockERC20("Reward Token", "RWD", 18, 0);
        receiptToken = new MockERC20("Receipt Token", "RCT", 18, 0);

        rewardToken.addMinter(address(diamond));
        receiptToken.addMinter(address(diamond));

        stakeToken.transfer(user, 1000e18);

        // ── Build cut ────────────────────────────
        FacetCut[] memory cut = new FacetCut[](4);

        cut[0] = FacetCut({
            facetAddress: address(loupe),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("DiamondLoupeFacet")
        });

        cut[1] = FacetCut({
            facetAddress: address(staking),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("StakingFacet")
        });

        cut[2] = FacetCut({
            facetAddress: address(viewFacet),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("StakingViewFacet")
        });

        cut[3] = FacetCut({
            facetAddress: address(admin),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("StakingAdminFacet")
        });

        // ── Upgrade diamond + init ───────────────
        IDiamondCut(address(diamond)).diamondCut(
            cut,
            address(init),
            abi.encodeCall(
                DiamondInit.init,
                (address(stakeToken), address(rewardToken), address(receiptToken))
            )
        );

        // sanity call
        DiamondLoupeFacet(address(diamond)).facetAddresses();
    }

    function test_Stake() public {
        vm.startPrank(user);

        stakeToken.approve(address(diamond), 100e18);
        StakingFacet(address(diamond)).stake(0, 100e18);

        vm.stopPrank();

        uint total = StakingViewFacet(address(diamond)).getPoolTotalStaked(0);
        assertEq(total, 100e18);
    }

    function test_ClaimRewards() public {
        vm.startPrank(user);

        stakeToken.approve(address(diamond), 100e18);
        StakingFacet(address(diamond)).stake(0, 100e18);

        vm.warp(block.timestamp + 100);

        uint beforeBal = rewardToken.balanceOf(user);
        StakingFacet(address(diamond)).claimRewards(0, 0);

        vm.stopPrank();

        uint afterBal = rewardToken.balanceOf(user);
        assertGt(afterBal, beforeBal);
    }

    function generateSelectors(
        string memory _facetName
    ) internal returns (bytes4[] memory selectors) {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "scripts/genSelectors.js";
        cmd[2] = _facetName;
        bytes memory res = vm.ffi(cmd);
        selectors = abi.decode(res, (bytes4[]));
    }


    function diamondCut(
        FacetCut[] calldata,
        address,
        bytes calldata
    ) external override {}
}
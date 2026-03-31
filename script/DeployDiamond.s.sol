// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import {Diamond} from "../src/Diamond.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {DiamondInit} from "../src/DiamondInit.sol";
import {StakingFacet} from "../src/facets/StakingFacet.sol";
import {StakingViewFacet} from "../src/facets/StakingViewFacet.sol";
import {StakingAdminFacet} from "../src/facets/StakingAdminFacet.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";

contract DeployDiamond is Script {
    // State vars shared across helpers — avoids packing everything into run()
    MockERC20 stakeToken;
    MockERC20 rewardToken;
    MockERC20 receiptToken;
    Diamond diamond;
    DiamondCutFacet cutFacet;
    DiamondLoupeFacet loupeFacet;
    DiamondInit initHelper;
    StakingFacet stakingFacet;
    StakingViewFacet viewFacet;
    StakingAdminFacet adminFacet;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        _deployTokens();
        _deployCore();
        _deployStakingFacets();
        _grantMinterRights();
        _cutDiamond();

        console.log("--- Deployment complete ---");
        console.log("Diamond     :", address(diamond));
        console.log("StakeToken  :", address(stakeToken));
        console.log("RewardToken :", address(rewardToken));
        console.log("ReceiptToken:", address(receiptToken));

        vm.stopBroadcast();
    }

    function _deployTokens() internal {
        stakeToken = new MockERC20("Stake Token", "STK", 18, 1_000_000e18);
        rewardToken = new MockERC20("Reward Token", "RWD", 18, 0);
        receiptToken = new MockERC20("Receipt Token", "RCT", 18, 0);
        console.log("StakeToken  :", address(stakeToken));
        console.log("RewardToken :", address(rewardToken));
        console.log("ReceiptToken:", address(receiptToken));
    }

    function _deployCore() internal {
        cutFacet = new DiamondCutFacet();
        loupeFacet = new DiamondLoupeFacet();
        initHelper = new DiamondInit();
        diamond = new Diamond(msg.sender, address(cutFacet));
        console.log("DiamondCutFacet  :", address(cutFacet));
        console.log("DiamondLoupeFacet:", address(loupeFacet));
        console.log("Diamond          :", address(diamond));
    }

    function _deployStakingFacets() internal {
        stakingFacet = new StakingFacet();
        viewFacet = new StakingViewFacet();
        adminFacet = new StakingAdminFacet();
        console.log("StakingFacet     :", address(stakingFacet));
        console.log("StakingViewFacet :", address(viewFacet));
        console.log("StakingAdminFacet:", address(adminFacet));
    }

    function _grantMinterRights() internal {
        rewardToken.addMinter(address(diamond));
        receiptToken.addMinter(address(diamond));
    }

    function _cutDiamond() internal {
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](4);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(loupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _loupeSelectors()
        });
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(stakingFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _stakingSelectors()
        });
        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: address(viewFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _viewSelectors()
        });
        cuts[3] = IDiamondCut.FacetCut({
            facetAddress: address(adminFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _adminSelectors()
        });

        bytes memory initCalldata =
            abi.encodeCall(DiamondInit.init, (address(stakeToken), address(rewardToken), address(receiptToken)));

        IDiamondCut(address(diamond)).diamondCut(cuts, address(initHelper), initCalldata);
        console.log("diamondCut complete - 4 pools initialized");
    }

    // ── Selector helpers ───────────────────────────────────────────────────

    function _loupeSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = IDiamondLoupe.facets.selector;
        s[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        s[2] = IDiamondLoupe.facetAddresses.selector;
        s[3] = IDiamondLoupe.facetAddress.selector;
    }

    function _stakingSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = StakingFacet.stake.selector;
        s[1] = StakingFacet.withdraw.selector;
        s[2] = StakingFacet.emergencyWithdraw.selector;
        s[3] = StakingFacet.claimRewards.selector;
    }

    function _viewSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](6);
        s[0] = StakingViewFacet.getPoolTotalStaked.selector;
        s[1] = StakingViewFacet.getPendingReward.selector;
        s[2] = StakingViewFacet.getStake.selector;
        s[3] = StakingViewFacet.getStakeCount.selector;
        s[4] = StakingViewFacet.getPoolRewardRate.selector;
        s[5] = StakingViewFacet.getPoolCount.selector;
    }

    function _adminSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = StakingAdminFacet.updateRewardRate.selector;
        s[1] = StakingAdminFacet.createPool.selector;
    }
}

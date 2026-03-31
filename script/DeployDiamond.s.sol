// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import { Diamond }            from "../src/Diamond.sol";
import { DiamondCutFacet }    from "../src/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet }  from "../src/facets/DiamondLoupeFacet.sol";
import { DiamondInit }        from "../src/DiamondInit.sol";
import { StakingFacet }       from "../src/facets/StakingFacet.sol";
import { StakingViewFacet }   from "../src/facets/StakingViewFacet.sol";
import { StakingAdminFacet }  from "../src/facets/StakingAdminFacet.sol";
import { MockERC20 }          from "../src/tokens/MockERC20.sol";
import { IDiamondCut }        from "../src/interfaces/IDiamondCut.sol";
import { IDiamondLoupe }      from "../src/interfaces/IDiamondLoupe.sol";

contract DeployDiamond is Script {

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // ── 1. Tokens ──────────────────────────────────────────────────────
        MockERC20 stakeToken   = new MockERC20("Stake Token",   "STK", 18, 1_000_000e18);
        MockERC20 rewardToken  = new MockERC20("Reward Token",  "RWD", 18, 0);
        MockERC20 receiptToken = new MockERC20("Receipt Token", "RCT", 18, 0);

        console.log("StakeToken  :", address(stakeToken));
        console.log("RewardToken :", address(rewardToken));
        console.log("ReceiptToken:", address(receiptToken));

        // ── 2. Diamond core ────────────────────────────────────────────────
        DiamondCutFacet   cutFacet   = new DiamondCutFacet();
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        DiamondInit       initHelper = new DiamondInit();
        Diamond           diamond    = new Diamond(deployer, address(cutFacet));

        console.log("DiamondCutFacet  :", address(cutFacet));
        console.log("DiamondLoupeFacet:", address(loupeFacet));
        console.log("Diamond          :", address(diamond));

        // ── 3. Staking facets ──────────────────────────────────────────────
        StakingFacet      stakingFacet = new StakingFacet();
        StakingViewFacet  viewFacet    = new StakingViewFacet();
        StakingAdminFacet adminFacet   = new StakingAdminFacet();

        console.log("StakingFacet     :", address(stakingFacet));
        console.log("StakingViewFacet :", address(viewFacet));
        console.log("StakingAdminFacet:", address(adminFacet));

        // ── 4. Grant Diamond minter rights ──────────────────────────────────
        rewardToken.addMinter(address(diamond));
        receiptToken.addMinter(address(diamond));

        // ── 5. One-shot diamondCut: attach all facets + run DiamondInit ─────
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](4);

        bytes4[] memory loupeSelectors = new bytes4[](4);
        loupeSelectors[0] = IDiamondLoupe.facets.selector;
        loupeSelectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupe.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupe.facetAddress.selector;

        bytes4[] memory stakingSelectors = new bytes4[](4);
        stakingSelectors[0] = StakingFacet.stake.selector;
        stakingSelectors[1] = StakingFacet.withdraw.selector;
        stakingSelectors[2] = StakingFacet.emergencyWithdraw.selector;
        stakingSelectors[3] = StakingFacet.claimRewards.selector;

        bytes4[] memory viewSelectors = new bytes4[](6);
        viewSelectors[0] = StakingViewFacet.getPoolTotalStaked.selector;
        viewSelectors[1] = StakingViewFacet.getPendingReward.selector;
        viewSelectors[2] = StakingViewFacet.getStake.selector;
        viewSelectors[3] = StakingViewFacet.getStakeCount.selector;
        viewSelectors[4] = StakingViewFacet.getPoolRewardRate.selector;
        viewSelectors[5] = StakingViewFacet.getPoolCount.selector;

        bytes4[] memory adminSelectors = new bytes4[](2);
        adminSelectors[0] = StakingAdminFacet.updateRewardRate.selector;
        adminSelectors[1] = StakingAdminFacet.createPool.selector;

        cuts[0] = IDiamondCut.FacetCut({ facetAddress: address(loupeFacet),   action: IDiamondCut.FacetCutAction.Add, functionSelectors: loupeSelectors   });
        cuts[1] = IDiamondCut.FacetCut({ facetAddress: address(stakingFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: stakingSelectors });
        cuts[2] = IDiamondCut.FacetCut({ facetAddress: address(viewFacet),    action: IDiamondCut.FacetCutAction.Add, functionSelectors: viewSelectors    });
        cuts[3] = IDiamondCut.FacetCut({ facetAddress: address(adminFacet),   action: IDiamondCut.FacetCutAction.Add, functionSelectors: adminSelectors   });

        IDiamondCut(address(diamond)).diamondCut(
            cuts,
            address(initHelper),
            abi.encodeCall(DiamondInit.init, (address(stakeToken), address(rewardToken), address(receiptToken)))
        );

        console.log("Diamond fully initialized. Pools: 4");

        vm.stopBroadcast();
    }
}

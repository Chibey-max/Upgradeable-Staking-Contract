# Diamond Staking — EIP-2535

Your `DefiStaking.sol` contract refactored as an upgradeable Diamond (EIP-2535).

## Project structure

```
diamond-staking/
├── foundry.toml
├── README.md
│
├── src/
│   ├── Diamond.sol                        # Proxy — delegatecalls to facets
│   ├── DiamondInit.sol                    # One-shot initializer (seeds pools + token addrs)
│   │
│   ├── interfaces/
│   │   ├── IDiamondCut.sol
│   │   ├── IDiamondLoupe.sol
│   │   └── ITokens.sol                    # IERC20 / IRewardToken / IReceiptToken
│   │
│   ├── libraries/
│   │   ├── LibDiamond.sol                 # Diamond storage + cut/replace/remove logic
│   │   └── LibStaking.sol                 # Staking state in its own storage slot
│   │
│   ├── facets/
│   │   ├── DiamondCutFacet.sol            # Registered at construction; drives upgrades
│   │   ├── DiamondLoupeFacet.sol          # EIP-2535 introspection
│   │   ├── StakingFacet.sol               # stake / withdraw / emergencyWithdraw / claimRewards
│   │   ├── StakingViewFacet.sol           # getPoolTotalStaked / getPendingReward / …  (V1)
│   │   ├── StakingViewFacetV2.sol         # Upgraded view — used in Replace test
│   │   └── StakingAdminFacet.sol          # updateRewardRate / createPool  (owner-only)
│   │
│   └── tokens/
│       └── MockERC20.sol                  # Mintable/burnable ERC-20 for tests
│
├── test/
│   └── deployDiamond.t.sol                # Full Foundry test suite
│
└── script/
    └── DeployDiamond.s.sol                # Broadcast deploy script
```

## How the staking contract was split

| Original `DefiStaking` function | Facet |
|---|---|
| `stake` | `StakingFacet` |
| `withdraw` | `StakingFacet` |
| `emergencyWithdraw` | `StakingFacet` |
| `claimRewards` | `StakingFacet` |
| `getPoolTotalStaked` | `StakingViewFacet` |
| `getPendingReward` | `StakingViewFacet` |
| `updateRewardRate` | `StakingAdminFacet` |
| constructor pool creation | `DiamondInit.init()` |

All state lives in `LibStaking.StakingStorage` at a fixed storage slot (`keccak256("diamond.storage.staking")`), so every facet reads/writes the same data through the Diamond proxy without storage collisions.

## Diamond cut actions tested

### Add
- Registers all four facets (Loupe + 3 staking facets) in a single `diamondCut` call
- `DiamondInit.init()` is delegatecalled to seed token addresses and create the 4 pools
- Verifies each selector routes to the correct facet via `IDiamondLoupe.facetAddress()`
- Reverts on duplicate selectors, non-owner cuts, and zero-address facets

### Replace
- Swaps `StakingViewFacet` → `StakingViewFacetV2` without touching `StakingFacet` or `StakingAdminFacet`
- Confirms selectors now resolve to V2
- Confirms total facet count is unchanged (in-place swap)
- Confirms on-chain state is preserved after the upgrade
- Reverts if same address or selector not yet registered

### Remove
- Strips `StakingAdminFacet` — permanently locks reward rates
- `updateRewardRate` resolves to `address(0)` afterwards
- Any call to removed functions reverts through the Diamond fallback
- `StakingFacet` and `StakingViewFacet` continue working normally
- Reverts if selector never existed or if `facetAddress != address(0)`

## Quick start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Install forge-std
forge install foundry-rs/forge-std --no-commit

# Run all tests
forge test -vv

# Run a specific test
forge test --match-test test_Replace_ViewFacetWithV2 -vvv

# Deploy locally
forge script script/DeployDiamond.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to a testnet (set PRIVATE_KEY in .env first)
source .env
forge script script/DeployDiamond.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## Key design points

**Storage isolation** — `LibDiamond` and `LibStaking` each use their own `keccak256`-derived storage slot. Adding a new facet can never overwrite another facet's variables.

**DiamondInit** — replaces the `constructor` from `DefiStaking.sol`. Because the Diamond is a proxy, constructors on facets don't run. `DiamondInit.init()` is delegatecalled once during the first `diamondCut`, seeding the four default pools and token addresses.

**Minter rights** — `rewardToken` and `receiptToken` must grant minter rights to the Diamond address (not to individual facets), since all calls are delegatecalled from the Diamond's context.

**Upgrading** — to ship a new version of any facet:
1. Deploy the new facet contract
2. Call `diamondCut` with `FacetCutAction.Replace` and the selectors you want to move
3. Old facet contract becomes unused; state is untouched

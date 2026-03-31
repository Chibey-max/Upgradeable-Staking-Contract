// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { IDiamondLoupe } from "../interfaces/IDiamondLoupe.sol";

// ─────────────────────────────────────────────────────────────────────────────
// DiamondLoupeFacet
// Implements EIP-2535 introspection: list all facets, selectors, and look up
// which facet a given selector is routed to.
// ─────────────────────────────────────────────────────────────────────────────

contract DiamondLoupeFacet is IDiamondLoupe {

    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 numSelectors = ds.selectors.length;
        facets_ = new Facet[](numSelectors);
        uint256[] memory numFacetSelectors = new uint256[](numSelectors);
        uint256 numFacets;

        for (uint256 i; i < numSelectors; i++) {
            bytes4 selector = ds.selectors[i];
            address facetAddr = ds.facetAddressAndSelectorPosition[selector].facetAddress;
            bool continueLoop;

            for (uint256 j; j < numFacets; j++) {
                if (facets_[j].facetAddress == facetAddr) {
                    facets_[j].functionSelectors[numFacetSelectors[j]] = selector;
                    numFacetSelectors[j]++;
                    continueLoop = true;
                    break;
                }
            }

            if (!continueLoop) {
                facets_[numFacets].facetAddress = facetAddr;
                facets_[numFacets].functionSelectors = new bytes4[](numSelectors);
                facets_[numFacets].functionSelectors[0] = selector;
                numFacetSelectors[numFacets] = 1;
                numFacets++;
            }
        }

        // Trim arrays to actual length
        for (uint256 i; i < numFacets; i++) {
            uint256 count = numFacetSelectors[i];
            bytes4[] memory trimmed = new bytes4[](count);
            for (uint256 j; j < count; j++) {
                trimmed[j] = facets_[i].functionSelectors[j];
            }
            facets_[i].functionSelectors = trimmed;
        }

        assembly { mstore(facets_, numFacets) }
    }

    function facetFunctionSelectors(address _facet) external view override returns (bytes4[] memory selectors_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 numSelectors = ds.selectors.length;
        selectors_ = new bytes4[](numSelectors);
        uint256 count;

        for (uint256 i; i < numSelectors; i++) {
            bytes4 sel = ds.selectors[i];
            if (ds.facetAddressAndSelectorPosition[sel].facetAddress == _facet) {
                selectors_[count] = sel;
                count++;
            }
        }

        assembly { mstore(selectors_, count) }
    }

    function facetAddresses() external view override returns (address[] memory addresses_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 numSelectors = ds.selectors.length;
        addresses_ = new address[](numSelectors);
        uint256 count;

        for (uint256 i; i < numSelectors; i++) {
            address addr = ds.facetAddressAndSelectorPosition[ds.selectors[i]].facetAddress;
            bool found;
            for (uint256 j; j < count; j++) {
                if (addresses_[j] == addr) { found = true; break; }
            }
            if (!found) { addresses_[count] = addr; count++; }
        }

        assembly { mstore(addresses_, count) }
    }

    function facetAddress(bytes4 _functionSelector) external view override returns (address) {
        return LibDiamond.diamondStorage().facetAddressAndSelectorPosition[_functionSelector].facetAddress;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { IDiamondCut } from "../interfaces/IDiamondCut.sol";

// ─────────────────────────────────────────────────────────────────────────────
// DiamondCutFacet
// The only facet registered in the Diamond constructor. Gives the owner the
// ability to add, replace, and remove any other facet.
// ─────────────────────────────────────────────────────────────────────────────

contract DiamondCutFacet is IDiamondCut {

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.FacetCut[] memory cut = new LibDiamond.FacetCut[](_diamondCut.length);
        for (uint256 i; i < _diamondCut.length; i++) {
            cut[i] = LibDiamond.FacetCut({
                facetAddress:      _diamondCut[i].facetAddress,
                action:            LibDiamond.FacetCutAction(uint8(_diamondCut[i].action)),
                functionSelectors: _diamondCut[i].functionSelectors
            });
        }
        LibDiamond.diamondCut(cut, _init, _calldata);
    }
}

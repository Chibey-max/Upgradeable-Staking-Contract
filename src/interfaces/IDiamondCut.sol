// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IDiamondCut {
    enum FacetCutAction {
        Add,
        Replace,
        Remove
    }

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    /// @notice Add, replace, or remove facet functions
    /// @param _diamondCut Array of facet cuts to apply
    /// @param _init       Address to delegatecall for initialization (address(0) = skip)
    /// @param _calldata   Calldata for _init
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external;

    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IDiamondLoupe {
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    /// @notice Returns all facets and their selectors
    function facets() external view returns (Facet[] memory facets_);

    /// @notice Returns all selectors registered to a given facet
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory);

    /// @notice Returns all facet addresses in the Diamond
    function facetAddresses() external view returns (address[] memory);

    /// @notice Returns the facet that implements the given selector
    function facetAddress(bytes4 _functionSelector) external view returns (address);
}

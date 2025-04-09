// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


import { ERC6909 } from "solmate/tokens/ERC6909.sol";
import { IERC6909TokenSupply } from "./interfaces/IERC6909TokenSupply.sol";
import { IERC6909ContentURI } from "./interfaces/IERC6909ContentURI.sol";


/// @title 3wb.club fleet order book V1.0
/// @notice Manages orders for fractional and full investments in 3-wheelers
/// @author Geeloko


contract FleetOrderBook is ERC6909, IERC6909TokenSupply, IERC6909ContentURI{
    /// @notice Total supply of a token.
    mapping(uint256 id => uint256) public totalSupply;

    /// @notice The contract level URI.
    string public contractURI;

    /// @notice The URI for each id.
    /// @return The URI of the token.
    function tokenURI(uint256) public pure override returns (string memory) {
        return "<baseuri>/{id}";
    }
}

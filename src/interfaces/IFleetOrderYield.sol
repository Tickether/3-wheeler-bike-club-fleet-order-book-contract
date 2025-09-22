// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title 3wb.club fleet order book interface V1.0
/// @notice interface for pre-orders for fractional and full investments in 3-wheelers
/// @author Geeloko

interface IFleetOrderYield {

    /// @notice Get the total payments distributed to a fleet order
    /// @param id The id of the fleet order
    /// @return The total payments distributed to the fleet order
    function getFleetPaymentsDistributed(uint256 id) external view returns (uint256);

}

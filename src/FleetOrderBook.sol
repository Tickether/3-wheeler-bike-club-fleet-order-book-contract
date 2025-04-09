// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


import { ERC6909 } from "solmate/tokens/ERC6909.sol";
import { IERC6909TokenSupply } from "./interfaces/IERC6909TokenSupply.sol";
import { IERC6909ContentURI } from "./interfaces/IERC6909ContentURI.sol";


/// @title 3wb.club fleet order book V1.0
/// @notice Manages orders for fractional and full investments in 3-wheelers
/// @author Geeloko


contract FleetOrderBook is ERC6909, IERC6909TokenSupply, IERC6909ContentURI{
    /// @notice Total supply of a ids reprsenting fleet orders.
    uint256 public totalFleet;
    /// @notice Last fleet fraction ID.
    uint256 public lastFleetFractionID;
    /// @notice Maximum number of fleet orders.
    uint256 public maxFleetOrder;
    
    /// @notice  price per fleet fraction.
    uint256 public fleetFractionPrice = 46;
    /// @notice Maximum number of fractions per fleet order.
    uint256 public immutable maxFleetFraction = 50;
    
    
    
    /// @notice Total fractions of a token representing a 3-wheeler.
    mapping(uint256 id => uint256) public totalFractions;

    /// @notice The contract level URI.
    string public contractURI;
    

    /// @notice Order a fleet onchain.
    /// @param fractions The number of fractions to order.
    function orderFleetOnchain ( uint256 fractions ) external virtual {

        require (fractions > 0);         
        require (totalFleet <= maxFleetOrder);
        require (fractions <= maxFleetFraction);

        // if minting all fractions
        if (fractions == maxFleetFraction) {
            totalFleet++;
            _mint(msg.sender, totalFleet + 1, 1);
        }

        // if minting some fractions
        if (fractions < maxFleetFraction) {
            // if first mint ie no last fleetFraction ID we create one
            if (lastFleetFractionID < 1) {
                totalFleet++;
                totalFractions[totalFleet + 1] = totalFractions[totalFleet + 1] + fractions;
                _mint(msg.sender, lastFleetFractionID, fractions);
            
            // if not first mint
            } else {
                // check fraction left of last token id
                uint256 fractionsLeft = maxFleetFraction - totalFractions[lastFleetFractionID];

                // if fractions Left is zero ie last fraction quota completely filled
                if (fractionsLeft < 1) {
                    totalFleet++;
                    totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
                    _mint(msg.sender, lastFleetFractionID, fractions);
                } else {
                    if (fractions <= fractionsLeft) {
                        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
                        _mint(msg.sender, lastFleetFractionID, fractions);
                    } else {
                        // check overflow value 
                        uint256 overflowFractions = fractions - fractionsLeft;

                        // mint what is posible then...
                        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractionsLeft;
                        _mint(msg.sender, lastFleetFractionID, fractionsLeft);
                        
                        //...mint overflow
                        totalFleet++;
                        totalFractions[totalFleet + 1] = totalFractions[totalFleet + 1] + overflowFractions;
                        _mint(msg.sender, lastFleetFractionID, overflowFractions);
                    }
                }
            }
        }

    }
    

/*
    function orderFleetOffchain ( uint256 fractions ) external {
        
    }
*/


    /// @notice The URI for each id.
    /// @return The URI of the token.
    function tokenURI(uint256) public pure override returns (string memory) {
        return "<baseuri>/{id}";
    }
}

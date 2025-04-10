// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
//import { Ownable } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
//import { Strings } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol";
import { ERC6909 } from "solmate/tokens/ERC6909.sol";
//import { ERC6909 } from  "https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC6909.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import { IERC20 } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import { IERC6909TokenSupply } from "./interfaces/IERC6909TokenSupply.sol";
import { IERC6909ContentURI } from "./interfaces/IERC6909ContentURI.sol";


/// @title 3wb.club fleet order book V1.0
/// @notice Manages orders for fractional and full investments in 3-wheelers
/// @author Geeloko


contract FleetOrderBook is Ownable, ERC6909, IERC6909TokenSupply, IERC6909ContentURI {
    using Strings for uint256;
    
    constructor() Ownable(_msgSender()) { }
    
    /// @notice Total supply of a ids reprsenting fleet orders.
    uint256 public totalFleet;
    /// @notice Last fleet fraction ID.
    uint256 public lastFleetFractionID;
    /// @notice track nodes ERC20 list
    address[] public fleetERC20s;
 
    /// @notice Maximum number of fleet orders.
    uint256 public MAX_FLEET_ORDER = 24;
    /// @notice  price per fleet fraction.
    uint256 public FLEET_FRACTION_PRICE = 46;
    /// @notice Maximum number of fractions per fleet order.
    uint256 public immutable MAX_FLEET_FRACTION = 50;
    
    /// @notice Total fractions of a token representing a 3-wheeler.
    mapping(uint256 id => uint256) public totalFractions;
    
    /// @notice The contract level URI.
    string public contractURI;
    

    /// @notice Set the contract level URI.
    /// @param _contractURI The URI to set.
    function setContractURI(string memory _contractURI) external onlyOwner {
        contractURI = _contractURI;
    }   


    /// @notice Set the fleet fraction price.
    /// @param fleetFractionPrice The price to set.
    function setFleetFractionPrice(uint256 fleetFractionPrice) external onlyOwner {
        FLEET_FRACTION_PRICE = fleetFractionPrice;
    }


    /// @notice Set the maximum number of fleet orders.
    /// @param maxFleetOrder The maximum number of fleet orders to set.    
    function setMaxFleetOrder(uint256 maxFleetOrder) external onlyOwner {
        MAX_FLEET_ORDER = maxFleetOrder;
    }


    /// @notice Pay fee in ERC20.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function payFeeERC20(uint256 fractions, address erc20Contract) 
        internal 
    {
        IERC20 tokenContract = IERC20(erc20Contract);
        uint256 price = FLEET_FRACTION_PRICE * fractions;
        require(tokenContract.balanceOf(msg.sender) >= (price * (1 * (10 ** 18))), 'not enough tokens');
        bool transferred = tokenContract.transferFrom( msg.sender, address(this), (price * (1 * (10 ** 18))) );
        require(transferred, "failed transfer"); 
    }


    /// @notice Order a fleet onchain.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function orderFleet ( uint256 fractions, address erc20Contract ) external virtual {

        require (fractions > 0, "fractions must be greater than 0");         
        require (totalFleet <= MAX_FLEET_ORDER, "totalFleet cannot exceed maxFleetOrder");
        require (fractions <= MAX_FLEET_FRACTION, "fractions cannot exceed maxFleetFraction");

        // if minting all fractions
        if (fractions == MAX_FLEET_FRACTION) {
            //pay fee
            payFeeERC20(fractions, erc20Contract);
            // mint fractions
            totalFleet++;
            _mint(msg.sender, totalFleet, 1);
        }

        // if minting some fractions
        if (fractions < MAX_FLEET_FRACTION) {
            // if first mint ie no last fleetFraction ID we create one
            if (lastFleetFractionID < 1) {
                // pay fee
                payFeeERC20(fractions, erc20Contract);
                // mint fractions
                totalFleet++;
                lastFleetFractionID = totalFleet;
                totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
                _mint(msg.sender, lastFleetFractionID, fractions);
            
            // if not first mint
            } else {
                // check fraction left of last token id
                uint256 fractionsLeft = MAX_FLEET_FRACTION - totalFractions[lastFleetFractionID];

                // if fractions Left is zero ie last fraction quota completely filled
                if (fractionsLeft < 1) {
                    // pay fee
                    payFeeERC20(fractions, erc20Contract);
                    // mint fractions
                    totalFleet++;
                    lastFleetFractionID = totalFleet;
                    totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
                    _mint(msg.sender, lastFleetFractionID, fractions);
                } else {
                    if (fractions <= fractionsLeft) {
                        //pay fee
                        payFeeERC20(fractions, erc20Contract);
                        // mint fractions
                        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
                        _mint(msg.sender, lastFleetFractionID, fractions);
                    } else {
                        //pay fee
                        payFeeERC20(fractions, erc20Contract);
                        
                        // check overflow value 
                        uint256 overflowFractions = fractions - fractionsLeft;

                        // mint what is posible then...
                        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractionsLeft;
                        _mint(msg.sender, lastFleetFractionID, fractionsLeft);
                        
                        //...mint overflow
                        totalFleet++;
                        lastFleetFractionID = totalFleet;
                        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + overflowFractions;
                        _mint(msg.sender, lastFleetFractionID, overflowFractions);
                    }
                }
            }
        }

    }
    

    /// @notice The URI for each id.
    /// @return The URI of the token.
    function tokenURI(uint256 id) public view override returns (string memory) {
        string memory baseURI = contractURI;
        return bytes(baseURI).length > 0 ? string.concat(baseURI, id.toString()) : "";
    }
}

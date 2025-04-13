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
/// @notice Manages pre-orders for fractional and full investments in 3-wheelers
/// @author Geeloko


contract FleetOrderBook is Ownable, ERC6909, IERC6909TokenSupply, IERC6909ContentURI {
    using Strings for uint256;

    /// @notice Event emitted when a fleet order is placed.
    event FleetOrdered(uint256 indexed fleetId, address indexed buyer);
    /// @notice Event emitted when a fleet fraction order is placed.
    event FleetFractionOrdered(uint256 indexed fleetId, address indexed buyer, uint256 indexed fractions);
    /// @notice Event emitted when an ERC20 token is added to the fleet.
    event ERC20Added(address indexed token);
    /// @notice Event emitted when an ERC20 token is removed from the fleet.
    event ERC20Removed(address indexed token);
    /// @notice Event emitted when the fleet fraction price is changed.
    event FleetFractionPriceChanged(uint256 oldPrice, uint256 newPrice);
    /// @notice Event emitted when the maximum fleet orders is changed.
    event MaxFleetOrderChanged(uint256 oldMax, uint256 newMax);
    /// @notice Event emitted when the contract active status is changed.
    event ContractActiveStatusChanged(bool newStatus);
    
    constructor() Ownable(_msgSender()) { }
    
    /// @notice Total supply of a ids reprsenting fleet orders.
    uint256 public totalFleet;
    /// @notice Last fleet fraction ID.
    uint256 public lastFleetFractionID;
    /// @notice track nodes ERC20 list
    address[] public fleetERC20s;
 
    /// @notice Maximum number of fleet orders.
    uint256 public MAX_FLEET_ORDER = 24;
    /// @notice  Price per fleet fraction  in USD.
    uint256 public FLEET_FRACTION_PRICE = 46;
    /// @notice Minimum number of fractions per fleet order.
    uint256 public immutable MIN_FLEET_FRACTION = 1;
    /// @notice Maximum number of fractions per fleet order.
    uint256 public immutable MAX_FLEET_FRACTION = 50;
     /// @notice Maximum number of fleet orders per address.
    uint256 public MAX_FLEET_ORDER_PER_ADDRESS = 100;
    /// @notice Number of decimals for the ERC20 token.
    uint256 public constant TOKEN_DECIMALS = 18;
    
    /// @notice owner => list of fleet order IDs
    mapping(address => uint256[]) private fleetOwned;
    /// @notice Total fractions of a token representing a 3-wheeler.
    mapping(uint256 id => uint256) public totalFractions;
    /// @notice Representing IRL fullfilled 3-wheeler fleet order.
    mapping(uint256 id => bool) public isFleetOrderFulfilled;
    
    /// @notice The contract level URI.
    string public contractURI;

    /// @notice The contract level active status.
    bool public active;


    /// @notice activate & deactivate the contract.
    function setActive() external onlyOwner {
        active = !active;
        emit ContractActiveStatusChanged(active);
    }
    

    /// @notice Set the contract level URI.
    /// @param _contractURI The URI to set.
    function setContractURI(string memory _contractURI) external onlyOwner {
        contractURI = _contractURI;
    }   


    /// @notice Set the fleet fraction price.
    /// @param fleetFractionPrice The price to set.
    function setFleetFractionPrice(uint256 fleetFractionPrice) external onlyOwner {
        require(fleetFractionPrice > 0, "fleetFractionPrice must be greater than 0");
        uint256 oldPrice = FLEET_FRACTION_PRICE;
        FLEET_FRACTION_PRICE = fleetFractionPrice;
        emit FleetFractionPriceChanged(oldPrice, fleetFractionPrice);
    }


    /// @notice Set the maximum number of fleet orders.
    /// @param maxFleetOrder The maximum number of fleet orders to set.    
    function setMaxFleetOrder(uint256 maxFleetOrder) external onlyOwner {
        require(maxFleetOrder > MAX_FLEET_ORDER, "maxFleetOrder must be greater than 0");
        uint256 oldMax = MAX_FLEET_ORDER;
        MAX_FLEET_ORDER = maxFleetOrder;
        emit MaxFleetOrderChanged(oldMax, maxFleetOrder);
    }


    /// @notice Add erc20contract to fleetERC20s.
    /// @param erc20Contract The address of the ERC20 contract.
    function addERC20(address erc20Contract) 
        external
        onlyOwner
    {
        require(fleetERC20s.length < 7, 'add limit reached');
        //req not on list... check for that
        for (uint i = 0; i < fleetERC20s.length; i++) {
            require(fleetERC20s[i] != erc20Contract, 'already added');
        }
        fleetERC20s.push(erc20Contract);
        emit ERC20Added(erc20Contract);
    }

    
    /// @notice remove erc20contract from fleetERC20s.
    /// @param erc20Contract The address of the ERC20 contract.
    function removeERC20(address erc20Contract) external onlyOwner {
        require(fleetERC20s.length > 0, 'nothing to remove');
        
        // Find and remove in a single loop
        for (uint256 i = 0; i < fleetERC20s.length; i++) {
            if (fleetERC20s[i] == erc20Contract) {
                // Move the last element to the position of the element to be removed
                fleetERC20s[i] = fleetERC20s[fleetERC20s.length - 1];
                // Remove the last element
                fleetERC20s.pop();
                emit ERC20Removed(erc20Contract);
                return;
            }
        }
        
        // If we get here, the token wasn't found
        revert('token not added');
    }
    

    /// @notice Pay fee in ERC20.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function payFeeERC20(uint256 fractions, address erc20Contract) 
        internal 
    {
        
        IERC20 tokenContract = IERC20(erc20Contract);
        uint256 price = FLEET_FRACTION_PRICE * fractions;
        require(tokenContract.balanceOf(msg.sender) >= (price * (1 * (10 ** TOKEN_DECIMALS))), 'not enough tokens');
        bool transferred = tokenContract.transferFrom( msg.sender, address(this), (price * (1 * (10 ** TOKEN_DECIMALS))) );
        require(transferred, "failed transfer"); 
    }


    /// @notice Check if a token is in the fleetERC20s list.
    /// @param token The address of the token to check.
    /// @return bool True if the token is in the list, false otherwise.
    function isTokenValid(address token) internal view returns (bool) {
        for (uint i = 0; i < fleetERC20s.length; i++) {
            if (fleetERC20s[i] == token) {
                return true;
            }
        }
        return false;
    }


    /// @notice Check if a fleet order is owned by an address.
    /// @param id The id of the fleet order to check.
    /// @return bool True if the fleet order is owned by the address, false otherwise.
    function isFleetOwned(uint256 id) internal view returns (bool) {
        for (uint i = 0; i < fleetOwned[msg.sender].length; i++) {
            if (fleetOwned[msg.sender][i] == id) {
                return true;
            }
        }
        return false;
    }

    /// @notice Order a fleet onchain.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function orderFleet ( uint256 fractions, address erc20Contract ) external virtual {
        
        require(fleetOwned[msg.sender].length <= MAX_FLEET_ORDER_PER_ADDRESS, "you have reached the maximum number of fleet orders");
        require(isTokenValid(erc20Contract), "ERC20 contract entered is not accepted for fleet orders");
        require(active, "Contract is not active");
        require(erc20Contract != address(0), "Invalid token address");
        require (fractions >= MIN_FLEET_FRACTION, "fractions start at 1, cannot be less");       
        require (fractions <= MAX_FLEET_FRACTION, "fractions cannot exceed maxFleetFraction");  
        require (totalFleet <= MAX_FLEET_ORDER, "totalFleet cannot exceed maxFleetOrder");
        

        // if minting all fractions
        if (fractions == MAX_FLEET_FRACTION) {
            //pay fee
            payFeeERC20(fractions, erc20Contract);
            // id counter
            totalFleet++;
            // add fleet order ID to fleetOwned
            fleetOwned[msg.sender].push(totalFleet);
            // mint fractions
            _mint(msg.sender, totalFleet, 1);
            emit FleetOrdered(totalFleet, msg.sender);
        }

        // if minting some fractions
        if (fractions < MAX_FLEET_FRACTION) {
            // if first mint ie no last fleetFraction ID we create one
            if (lastFleetFractionID < 1) {
                // pay fee
                payFeeERC20(fractions, erc20Contract);
                // id counter
                totalFleet++;
                lastFleetFractionID = totalFleet;
                totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
                // add fleet order ID to fleetOwned
                if (!isFleetOwned(totalFleet)) {
                    fleetOwned[msg.sender].push(totalFleet);
                }
                // mint fractions
                _mint(msg.sender, lastFleetFractionID, fractions);
                emit FleetFractionOrdered(lastFleetFractionID, msg.sender, fractions);

            // if not first mint
            } else {
                // check fraction left of last token id
                uint256 fractionsLeft = MAX_FLEET_FRACTION - totalFractions[lastFleetFractionID];

                // if fractions Left is zero ie last fraction quota completely filled
                if (fractionsLeft < 1) {
                    // pay fee
                    payFeeERC20(fractions, erc20Contract);
                    // id counter
                    totalFleet++;
                    lastFleetFractionID = totalFleet;
                    totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
                    // add fleet order ID to fleetOwned
                    if (!isFleetOwned(totalFleet)) {
                        fleetOwned[msg.sender].push(totalFleet);
                    }
                    // mint fractions
                    _mint(msg.sender, lastFleetFractionID, fractions);
                    emit FleetFractionOrdered(lastFleetFractionID, msg.sender, fractions);
                } else {
                    if (fractions <= fractionsLeft) {
                        //pay fee
                        payFeeERC20(fractions, erc20Contract);
                        // add fleet order ID to fleetOwned
                        if (!isFleetOwned(lastFleetFractionID)) {
                            fleetOwned[msg.sender].push(lastFleetFractionID);
                        }
                        // mint fractions
                        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
                        _mint(msg.sender, lastFleetFractionID, fractions);
                        emit FleetFractionOrdered(lastFleetFractionID, msg.sender, fractions);
                    } else {
                        //pay fee
                        payFeeERC20(fractions, erc20Contract);

                        // add fleet order ID to fleetOwned
                        if (!isFleetOwned(lastFleetFractionID)) {
                            fleetOwned[msg.sender].push(lastFleetFractionID);
                        }
                        
                        // check overflow value 
                        uint256 overflowFractions = fractions - fractionsLeft;

                        // mint what is posible then...
                        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractionsLeft;
                        _mint(msg.sender, lastFleetFractionID, fractionsLeft);
                        emit FleetFractionOrdered(lastFleetFractionID, msg.sender, fractionsLeft);
                        
                        // id counter
                        totalFleet++;
                        lastFleetFractionID = totalFleet;
                        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + overflowFractions;
                        // add fleet order ID to fleetOwned
                        fleetOwned[msg.sender].push(totalFleet);
                        //...mint overflow
                        _mint(msg.sender, lastFleetFractionID, overflowFractions);
                        emit FleetFractionOrdered(lastFleetFractionID, msg.sender, overflowFractions);
                    }
                }
            }
        }

    }


    /// @notice Get the fleet orders owned by an address.
    /// @param owner The address of the owner.
    /// @return The fleet orders owned by the address.
    function getFleetOwned(address owner) external view returns (uint256[] memory) {
        return fleetOwned[owner];
    }


    /// @notice Fullfill a fleet order.
    /// @param id The id of the fleet order to fullfill.
    function fullfillFleetOrder(uint256 id) external onlyOwner {
        require(id > 0, "id must be greater than 0");
        require(id <= totalFleet, "id does not exist in fleet");
        isFleetOrderFulfilled[id] = true;
    }
    

    /// @notice The URI for each id.
    /// @param id The id of the fleet order to get the URI for.
    /// @return The URI of the token.
    function tokenURI(uint256 id) public view override returns (string memory) {
        require(id > 0, "id must be greater than 0");
        require(id <= totalFleet, "id does not exist in fleet");
        string memory baseURI = contractURI;
        return bytes(baseURI).length > 0 ? string.concat(baseURI, id.toString()) : "";
    }


    /// @notice Remove a fleet order.
    /// @param id The id of the fleet order to remove.
    /// @param sender The address of the sender.
    function removeFleetOrder(uint256 id, address sender) internal {
        // Find and remove the id from fleetOwned for the specific owner
        for (uint256 i = 0; i < fleetOwned[sender].length; i++) {
            if (fleetOwned[sender][i] == id) {
                // Move the last element to the position of the element to be removed
                fleetOwned[sender][i] = fleetOwned[sender][fleetOwned[sender].length - 1];
                // Remove the last element
                fleetOwned[sender].pop();
                break;
            }
        }
    }


    /// @notice Transfer a fleet order.
    /// @param receiver The address of the receiver.
    /// @param id The id of the fleet order to transfer.
    /// @param amount The amount of fleet order to transfer.
    /// @return bool True if the transfer was successful, false otherwise.
    function transfer(
        address receiver,
        uint256 id,
        uint256 amount
    ) public override returns (bool) {
        require(id > 0, "id must be greater than 0");
        require(id <= totalFleet, "id does not exist in fleet");
        require(fleetOwned[receiver].length <= MAX_FLEET_ORDER_PER_ADDRESS, "you have reached the maximum number of fleet orders");
        
        balanceOf[msg.sender][id] -= amount;
        removeFleetOrder(id, msg.sender);

        balanceOf[receiver][id] += amount;
        fleetOwned[receiver].push(id);

        emit Transfer(msg.sender, msg.sender, receiver, id, amount);

        return true;
    }


    /// @notice Transfer a fleet order.
    /// @param sender The address of the sender.
    /// @param receiver The address of the receiver.
    /// @param id The id of the fleet order to transfer.
    /// @param amount The amount of fleet order to transfer.
    /// @return bool True if the transfer was successful, false otherwise.
    function transferFrom(
        address sender,
        address receiver,
        uint256 id,
        uint256 amount
    ) public override returns (bool) {
        require(id > 0, "id must be greater than 0");
        require(id <= totalFleet, "id does not exist in fleet");
        require(fleetOwned[receiver].length <= MAX_FLEET_ORDER_PER_ADDRESS, "you have reached the maximum number of fleet orders");

        if (msg.sender != sender && !isOperator[sender][msg.sender]) {
            uint256 allowed = allowance[sender][msg.sender][id];
            if (allowed != type(uint256).max) allowance[sender][msg.sender][id] = allowed - amount;
        }

        balanceOf[sender][id] -= amount;
        removeFleetOrder(id, sender);

        balanceOf[receiver][id] += amount;
        fleetOwned[receiver].push(id);

        emit Transfer(msg.sender, sender, receiver, id, amount);

        return true;
    }


    /// @notice Withdraw sales from fleet order book.
    /// @param token The address of the ERC20 contract.
    /// @param to The address to send the sales to.
    function withdrawFleetOrderSales(address token, address to) external onlyOwner {
        IERC20 tokenContract = IERC20(token);
        require(tokenContract.balanceOf(address(this)) > 0, 'not enough tokens');
        bool transferred = tokenContract.transfer(to, tokenContract.balanceOf(address(this)));
        require(transferred, "failed transfer"); 
    }

}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IERC6909TokenSupply } from "./interfaces/IERC6909TokenSupply.sol";
import { IERC6909ContentURI } from "./interfaces/IERC6909ContentURI.sol";

import { ERC6909 } from "solmate/tokens/ERC6909.sol";
//import { ERC6909 } from  "https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC6909.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
//import { Ownable } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
//import { Pausable } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
//import { ReentrancyGuard } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
//import { Strings } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import { IERC20 } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//import { SafeERC20 } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";



/// @title 3wb.club fleet order book V1.0
/// @notice Manages pre-orders for fractional and full investments in 3-wheelers
/// @author Geeloko


contract FleetOrderBook is IERC6909TokenSupply, IERC6909ContentURI, ERC6909, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Strings for uint256;
    

    /// @notice Event emitted when a fleet order is placed.
    event FleetOrdered(uint256 indexed fleetId, address indexed buyer);
    /// @notice Event emitted when a fleet fraction order is placed.
    event FleetFractionOrdered(uint256 indexed fleetId, address indexed buyer, uint256 indexed fractions);
    /// @notice Event emitted when fleet sales are withdrawn.
    event FleetSalesWithdrawn(address indexed token, address indexed to, uint256 amount);
    /// @notice Event emitted when a fleet order is fulfilled.
    event FleetOrderFulfilled(uint256 indexed id);
    /// @notice Event emitted when an ERC20 token is added to the fleet.
    event ERC20Added(address indexed token);
    /// @notice Event emitted when an ERC20 token is removed from the fleet.
    event ERC20Removed(address indexed token);
    /// @notice Event emitted when the fleet fraction price is changed.
    event FleetFractionPriceChanged(uint256 oldPrice, uint256 newPrice);
    /// @notice Event emitted when the maximum fleet orders is changed.
    event MaxFleetOrderChanged(uint256 oldMax, uint256 newMax);
    
    constructor() Ownable(_msgSender()) { }
    
    /// @notice Total supply of a ids representing fleet orders.
    uint256 public totalFleet;
    /// @notice Last fleet fraction ID.
    uint256 public lastFleetFractionID;    
 
    /// @notice Maximum number of fleet orders.
    uint256 public maxFleetOrder = 24;
    /// @notice  Price per fleet fraction  in USD.
    uint256 public fleetFractionPrice = 46;

    /// @notice Minimum number of fractions per fleet order.
    uint256 public immutable MIN_FLEET_FRACTION = 1;
    /// @notice Maximum number of fractions per fleet order.
    uint256 public immutable MAX_FLEET_FRACTION = 50;
     /// @notice Maximum number of fleet orders per address.
    uint256 public immutable MAX_FLEET_ORDER_PER_ADDRESS = 100;
    /// @notice Number of decimals for the ERC20 token.
    uint256 public constant TOKEN_DECIMALS = 18;
    
    /// @notice check if ERC20 is accepted for fleet orders
    mapping(address => bool) public fleetERC20;
    /// @notice owner => list of fleet order IDs
    mapping(address => uint256[]) private fleetOwned;
    /// @notice Total fractions of a token representing a 3-wheeler.
    mapping(uint256 id => uint256) public totalFractions;
    /// @notice Representing IRL fulfilled 3-wheeler fleet order.
    mapping(uint256 id => bool) public isFleetOrderFulfilled;
    /// @notice tracking fleet order index for each owner
    mapping(address => mapping(uint256 => uint256)) private fleetOwnedIndex;
    
    /// @notice The contract level URI.
    string public contractURI;
    

    /// @notice Pause the contract 
    function pause() external onlyOwner {
        _pause();
    }


    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }


    /// @notice Set the contract level URI.
    /// @param _contractURI The URI to set.
    function setContractURI(string memory _contractURI) external onlyOwner {
        contractURI = _contractURI;
    }   


    /// @notice Set the fleet fraction price.
    /// @param _fleetFractionPrice The price to set.
    function setFleetFractionPrice(uint256 _fleetFractionPrice) external onlyOwner {
        require(_fleetFractionPrice > 0, "fleetFractionPrice must be greater than 0");
        uint256 oldPrice = fleetFractionPrice;
        fleetFractionPrice = _fleetFractionPrice;
        emit FleetFractionPriceChanged(oldPrice, _fleetFractionPrice);
    }


    /// @notice Set the maximum number of fleet orders.
    /// @param _maxFleetOrder The maximum number of fleet orders to set.    
    function setMaxFleetOrder(uint256 _maxFleetOrder) external onlyOwner {
        require(_maxFleetOrder > maxFleetOrder, "maxFleetOrder must be greater than the current maximum");
        uint256 oldMax = maxFleetOrder;
        maxFleetOrder = _maxFleetOrder;
        emit MaxFleetOrderChanged(oldMax, _maxFleetOrder);
    }


    /// @notice Add erc20contract to fleetERC20s.
    /// @param erc20Contract The address of the ERC20 contract.
    function addERC20(address erc20Contract) 
        external
        onlyOwner
    {
        require(!fleetERC20[erc20Contract], "Token already added");

        fleetERC20[erc20Contract] = true;
        emit ERC20Added(erc20Contract);
    }

    
    /// @notice remove erc20contract from fleetERC20s.
    /// @param erc20Contract The address of the ERC20 contract.
    function removeERC20(address erc20Contract) external onlyOwner {
        require(fleetERC20[erc20Contract], 'token not added');
        
        fleetERC20[erc20Contract] = false;
        emit ERC20Removed(erc20Contract);
    }
    

    /// @notice Pay fee in ERC20.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function payFeeERC20(uint256 fractions, address erc20Contract) 
        internal 
    {
        
        IERC20 tokenContract = IERC20(erc20Contract);
        uint256 price = fleetFractionPrice * fractions;
        uint256 amount = price * (10 ** TOKEN_DECIMALS);
        require(tokenContract.balanceOf(msg.sender) >= amount, 'not enough tokens');
        tokenContract.safeTransferFrom( msg.sender, address(this), amount );
    }


    /// @notice Check if a token is in the fleetERC20s list.
    /// @param erc20Contract The address of the token to check.
    /// @return bool True if the token is in the list, false otherwise.
    function isTokenValid(address erc20Contract) internal view returns (bool) {
        return fleetERC20[erc20Contract];
    }


    /// @notice Check if a fleet order is owned by an address.
    /// @param id The id of the fleet order to check.
    /// @return bool True if the fleet order is owned by the address, false otherwise.
    function isFleetOwned(address owner, uint256 id) internal view returns (bool) {
        // If no orders exist for msg.sender, return false immediately.
        if (fleetOwned[owner].length == 0) return false;
        
        // Retrieve the stored index for the order id.
        uint256 index = fleetOwnedIndex[owner][id];

        // If the index is out of range, then id is not owned.
        if (index >= fleetOwned[owner].length) return false;
        
        // Check that the order at that index matches the given id.
        return fleetOwned[owner][index] == id;
    }



    /// @notice Add a fleet order to the owner.
    /// @param receiver The address of the receiver.
    /// @param id The id of the fleet order to add.
    function addFleetOrder(address receiver, uint256 id) internal {
        fleetOwned[receiver].push(id);
        // Record the index for orderId in the owner's fleetOwned array.
        fleetOwnedIndex[receiver][id] = fleetOwned[receiver].length - 1;
    }


    /// @notice Remove a fleet order.
    /// @param id The id of the fleet order to remove.
    /// @param sender The address of the sender.
    function removeFleetOrder(uint256 id, address sender) internal {
        // Get the index of the orderId in the owner's fleetOwned array.
        uint256 indexToRemove = fleetOwnedIndex[sender][id];
        uint256 lastIndex = fleetOwned[sender].length - 1;

        // If the order being removed is not the last one, swap it with the last element.
        if (indexToRemove != lastIndex) {
            uint256 lastOrderId = fleetOwned[sender][lastIndex];
            fleetOwned[sender][indexToRemove] = lastOrderId;
            // Update the index mapping for the swapped order.
            fleetOwnedIndex[sender][lastOrderId] = indexToRemove;
        }
        
        // Remove the last element and delete the mapping entry for the removed order.
        fleetOwned[sender].pop();
        delete fleetOwnedIndex[sender][id];
    }


    /// @notice Handle a full fleet order.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function handleFullFleetOrder(uint256 fractions, address erc20Contract) internal {
        //pay fee
        payFeeERC20(fractions, erc20Contract);
        // id counter
        totalFleet++;
        // add fleet order ID to fleetOwned
        addFleetOrder(msg.sender, totalFleet);
        // mint fractions
        _mint(msg.sender, totalFleet, 1);
        emit FleetOrdered(totalFleet, msg.sender);   
    }


    /// @notice Handle an initial fractional fleet order.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function handleInitialFractionsFleetOrder(uint256 fractions, address erc20Contract) internal {
        // pay fee
        payFeeERC20(fractions, erc20Contract);
        // id counter
        totalFleet++;
        lastFleetFractionID = totalFleet;
        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
        // add fleet order ID to fleetOwned
        addFleetOrder(msg.sender, totalFleet);
        // mint fractions
        _mint(msg.sender, lastFleetFractionID, fractions);
        emit FleetFractionOrdered(lastFleetFractionID, msg.sender, fractions);
    }
    

    /// @notice Handle an additional fractional fleet order.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function handleAdditionalFractionsFleetOrder(uint256 fractions, address erc20Contract) internal {
        //pay fee
        payFeeERC20(fractions, erc20Contract);
        // add fleet order ID to fleetOwned
        if (!isFleetOwned(msg.sender, lastFleetFractionID)) {
            addFleetOrder(msg.sender, lastFleetFractionID);
        }
        // mint fractions
        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
        _mint(msg.sender, lastFleetFractionID, fractions);
        emit FleetFractionOrdered(lastFleetFractionID, msg.sender, fractions);
    }

   
    /// @notice Handle a fractional fleet order overflow.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    /// @param fractionsLeft The number of fractions left.
    function handleFractionsFleetOrderOverflow(uint256 fractions, address erc20Contract, uint256 fractionsLeft) internal {
        //pay fee
        payFeeERC20(fractions, erc20Contract);

        // add fleet order ID to fleetOwned
        if (!isFleetOwned(msg.sender, lastFleetFractionID)) {
            addFleetOrder(msg.sender, lastFleetFractionID);
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
        addFleetOrder(msg.sender, totalFleet);
        //...mint overflow
        _mint(msg.sender, lastFleetFractionID, overflowFractions);
        emit FleetFractionOrdered(lastFleetFractionID, msg.sender, overflowFractions);
    }
    

    /// @notice Order multiple fleet orders.
    /// @param amount The number of fleet orders to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function orderMultipleFleet(uint256 amount, address erc20Contract) external nonReentrant whenNotPaused {

        require(fleetOwned[msg.sender].length + amount <= MAX_FLEET_ORDER_PER_ADDRESS, "you have reached the maximum number of fleet orders");
        require(amount > 1, "must be multiple fleet orders");
        require(isTokenValid(erc20Contract), "ERC20 contract entered is not accepted for fleet orders");
        require(erc20Contract != address(0), "Invalid token address");
        require (totalFleet + amount <= maxFleetOrder, "totalFleet cannot exceed maxFleetOrder");
        for (uint256 i = 0; i < amount; i++) {
            handleFullFleetOrder(MAX_FLEET_FRACTION, erc20Contract);
        }
    }

    /// @notice Order a fleet onchain.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function orderFleet ( uint256 fractions, address erc20Contract ) external nonReentrant whenNotPaused{
        
        
        require(isTokenValid(erc20Contract), "ERC20 contract entered is not accepted for fleet orders");
        require(erc20Contract != address(0), "Invalid token address");
        require (fractions >= MIN_FLEET_FRACTION, "fractions start at 1, cannot be less");       
        require (fractions <= MAX_FLEET_FRACTION, "fractions cannot exceed maxFleetFraction");  
        
        

        // if minting all fractions
        if (fractions == MAX_FLEET_FRACTION) {
            require(fleetOwned[msg.sender].length + 1 <= MAX_FLEET_ORDER_PER_ADDRESS, "you have reached the maximum number of fleet orders");
            require (totalFleet + 1 <= maxFleetOrder, "totalFleet cannot exceed maxFleetOrder");
            handleFullFleetOrder(fractions, erc20Contract);
        }

        // if minting some fractions
        if (fractions < MAX_FLEET_FRACTION) {
            // if first mint ie no last fleetFraction ID we create one
            if (lastFleetFractionID < 1) {
                handleInitialFractionsFleetOrder(fractions, erc20Contract);
            // if not first mint
            } else {
                
                // check fraction left of last token id
                uint256 fractionsLeft = MAX_FLEET_FRACTION - totalFractions[lastFleetFractionID];

                // if fractions Left is zero ie last fraction quota completely filled
                if (fractionsLeft < 1) {
                    require(fleetOwned[msg.sender].length + 1 <= MAX_FLEET_ORDER_PER_ADDRESS, "you have reached the maximum number of fleet orders");
                    require (totalFleet + 1 <= maxFleetOrder, "totalFleet cannot exceed maxFleetOrder");
                    handleInitialFractionsFleetOrder(fractions, erc20Contract);
                } else {
                    if (fractions <= fractionsLeft) {
                        require(fleetOwned[msg.sender].length + 1 <= MAX_FLEET_ORDER_PER_ADDRESS, "you have reached the maximum number of fleet orders");
                        handleAdditionalFractionsFleetOrder(fractions, erc20Contract);
                    } else {
                        require(fleetOwned[msg.sender].length + 1 <= MAX_FLEET_ORDER_PER_ADDRESS, "you have reached the maximum number of fleet orders");
                        require (totalFleet + 1 <= maxFleetOrder, "totalFleet cannot exceed maxFleetOrder");
                        handleFractionsFleetOrderOverflow(fractions, erc20Contract, fractionsLeft);
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


    /// @notice Fulfill a fleet order.
    /// @param id The id of the fleet order to fulfill.
    function fulfillFleetOrder(uint256 id) external onlyOwner {
        require(id > 0, "id must be greater than 0");
        require(id <= totalFleet, "id does not exist in fleet");
        isFleetOrderFulfilled[id] = true;
        emit FleetOrderFulfilled(id);
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
        require(fleetOwned[receiver].length < MAX_FLEET_ORDER_PER_ADDRESS, "you have reached the maximum number of fleet orders");
        
        require(balanceOf[msg.sender][id] >= amount, "insufficient balance");
        // subtract first
        balanceOf[msg.sender][id] -= amount;
        // if they hold none left, then remove from their list
        if (balanceOf[msg.sender][id] == 0) {
            removeFleetOrder(id, msg.sender);
        }

        balanceOf[receiver][id] += amount;
        // add fleet order ID to fleetOwned
        if (!isFleetOwned(receiver, id)) {
            addFleetOrder(receiver, id);
        }

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
        require(fleetOwned[receiver].length < MAX_FLEET_ORDER_PER_ADDRESS, "you have reached the maximum number of fleet orders");

        if (msg.sender != sender && !isOperator[sender][msg.sender]) {
            uint256 allowed = allowance[sender][msg.sender][id];
            if (allowed != type(uint256).max) allowance[sender][msg.sender][id] = allowed - amount;
        }

        require(balanceOf[sender][id] >= amount, "insufficient balance");
        // subtract first
        balanceOf[sender][id] -= amount;
        // if they hold none left, then remove from their list
        if (balanceOf[sender][id] == 0) {
            removeFleetOrder(id, sender);
        }


        balanceOf[receiver][id] += amount;
        // add fleet order ID to fleetOwned
        if (!isFleetOwned(receiver, id)) {
            addFleetOrder(receiver, id);
        }
        
        emit Transfer(msg.sender, sender, receiver, id, amount);

        return true;
    }


    /// @notice Withdraw sales from fleet order book.
    /// @param token The address of the ERC20 contract.
    /// @param to The address to send the sales to.
    function withdrawFleetOrderSales(address token, address to) external onlyOwner nonReentrant {
        require(token != address(0), "Invalid token address");
        IERC20 tokenContract = IERC20(token);
        uint256 amount = tokenContract.balanceOf(address(this));
        require(amount > 0, 'not enough tokens');
        tokenContract.safeTransfer(to, amount);
        emit FleetSalesWithdrawn(token, to, amount);
    }

    receive() external payable { revert("no native token accepted"); }
    fallback() external payable { revert("no native token accepted"); }


}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


/// @dev Interface imports
import { IERC6909TokenSupply } from "./interfaces/IERC6909TokenSupply.sol";

/// @dev Solmate imports
import { ERC6909 } from "solmate/tokens/ERC6909.sol";
//import { ERC6909 } from  "https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC6909.sol";

/// @dev OpenZeppelin utils imports
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev OpenZeppelin access imports
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";



/// @title 3wb.club fleet order book V1.0
/// @notice Manages referral pre-orders for fractional and full investments in 3-wheelers
/// @author geeloko.eth



contract FleetOrderBookPreSale is IERC6909TokenSupply, ERC6909, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Strings for uint256;
    

    /// @notice Total supply of a ids representing fleet orders.
    uint256 public totalFleet;
    /// @notice Last fleet fraction ID.
    uint256 public lastFleetFractionID;    
    /// @notice Maximum number of fleet orders.
    uint256 public maxFleetOrder;
    /// @notice  Price per fleet fraction  in USD.
    uint256 public fleetFractionPrice;


    /// @notice State constants - each state is a power of 2 (bit position)
    uint256 constant INIT = 1 << 0;         // 00000001
    uint256 constant CREATED = 1 << 1;      // 00000010
    uint256 constant SHIPPED = 1 << 2;      // 00000100
    uint256 constant ARRIVED = 1 << 3;      // 00001000
    uint256 constant CLEARED = 1 << 4;      // 00010000
    uint256 constant REGISTERED = 1 << 5;   // 00100000
    uint256 constant ASSIGNED = 1 << 6;     // 01000000
    uint256 constant TRANSFERRED = 1 << 7;  // 10000000


    /// @notice Minimum number of fractions per fleet order.
    uint256 public constant MIN_FLEET_FRACTION = 1;
    /// @notice Maximum number of fractions per fleet order.
    uint256 public constant MAX_FLEET_FRACTION = 50;
     /// @notice Maximum number of fleet orders per address.
    uint256 public constant MAX_FLEET_ORDER_PER_ADDRESS = 100;
    /// @notice Maximum number of fleet orders that can be updated in bulk
    uint256 constant MAX_BULK_UPDATE = 50;
    /// @notice Maximum number of fleet orders that can be purchased in bulk
    uint256 constant MAX_ORDER_MULTIPLE_FLEET = 3;
    

    /// @notice Mapping to store the IRL fulfillment state of each 3-wheeler fleet order
    mapping(uint256 => uint256) public fleetOrderStatus;
    /// @notice check if ERC20 is accepted for fleet orders
    mapping(address => bool) public fleetERC20;
    /// @notice owner => list of fleet order IDs
    mapping(address => uint256[]) public fleetOwned;
    /// @notice fleet order ID => list of owners
    mapping(uint256 => address[]) public fleetOwners;
    /// @notice Total fractions of a token representing a 3-wheeler.
    mapping(uint256 => bool) public fleetFractioned;
    /// @notice Total fractions of a token representing a 3-wheeler.
    mapping(uint256 => uint256) public totalFractions;
    /// @notice tracking fleet order index for each owner
    mapping(address => mapping(uint256 => uint256)) private fleetOwnedIndex;
    /// @notice tracking owners index for each fleet order
    mapping(uint256 => mapping(address => uint256)) private fleetOwnersIndex;
    

    /*..............................................................*/
    // presale system + compliance variables 
    /*..............................................................*/
   
    /// @notice Whether a wallet is whitelisted for the presale.
    mapping(address => bool) public isWhitelisted;
    /// @notice Whether a wallet is compliant.
    mapping(address => bool) public isCompliant;
    /// @notice Whether a wallet is a referrer.
    mapping(address => bool) public isReferrer;
    /// @notice Mapping of referrer to referred.
    mapping(address => address) public referral;
    /// @notice Mapping of individual referred to total pool shares.
    mapping(address => uint256) public referralPoolShares;
    /// @notice Mapping of referrer to referrer pool shares.
    mapping(address => uint256) public referrerPoolShares;
    


    /// @notice Event emitted when a fleet order is placed.
    event FleetOrdered(uint256[] ids, address indexed buyer, uint256 indexed amount);
    /// @notice Event emitted when a fleet fraction order is placed.
    event FleetFractionOrdered(uint256 indexed id, address indexed buyer, uint256 indexed fractions);
    /// @notice Event emitted when a fleet fraction overflow order is placed.
    event FleetFractionOverflowOrdered(uint256[] ids, address indexed buyer, uint256[] fractions);
    /// @notice Event emitted when fleet sales are withdrawn.
    event FleetSalesWithdrawn(address indexed token, address indexed to, uint256 amount);
    /// @notice Event emitted when an ERC20 token is added to the fleet.
    event ERC20Added(address indexed token);
    /// @notice Event emitted when an ERC20 token is removed from the fleet.
    event ERC20Removed(address indexed token);
    /// @notice Event emitted when the fleet fraction price is changed.
    event FleetFractionPriceChanged(uint256 oldPrice, uint256 newPrice);
    /// @notice Event emitted when the maximum fleet orders is changed.
    event MaxFleetOrderChanged(uint256 oldMax, uint256 newMax);
    /// @notice Event emitted when a fleet order status changes.
    event FleetOrderStatusChanged(uint256 indexed id, uint256 status);
    /// @notice Event emitted when a wallet is whitelisted.
    event Whitelisted(address indexed referrer, address indexed owner);
    /// @notice Event emitted when a wallet is added as a referrer.
    event Referrered(address indexed referrer, address indexed referred, uint256 shares);


    /// @notice Error messages
    error InvalidStatus();
    error InvalidStateTransition();
    error DuplicateIds();
    error BulkUpdateLimitExceeded();
    error InvalidId();
    error IdDoesNotExist();
    error InvalidTokenAddress();
    error TokenNotAccepted();
    error InsufficientBalance();
    error MaxFleetOrderExceeded();
    error MaxOrderMultipleFleetExceeded();
    error MaxFleetOrderPerAddressExceeded();
    error InvalidFractionAmount();
    error FractionExceedsMax();
    error NotEnoughTokens();
    error InvalidAmount();
    error NoNativeTokenAccepted();
    error InvalidPrice();
    error MaxFleetOrderNotIncreased();
    error TokenAlreadyAdded();
    error TokenNotAdded();
    error InvalidReferrer();
    error NotReferrer();
    error AlreadyReferred();
    error NotWhitelisted();
    error AlreadyWhitelisted();
    error NotCompliant();
    error AlreadyCompliant();
    error CannotWhitelistReferrer();


    constructor() Ownable(msg.sender) {}


    /// @notice Pause the contract 
    function pause() external onlyOwner {
        _pause();
    }


    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }


    /// @notice Set the fleet fraction price.
    /// @param _fleetFractionPrice The price to set.
    function setFleetFractionPrice(uint256 _fleetFractionPrice) external onlyOwner {
        if (_fleetFractionPrice == 0) revert InvalidPrice();
        uint256 oldPrice = fleetFractionPrice;
        fleetFractionPrice = _fleetFractionPrice;
        emit FleetFractionPriceChanged(oldPrice, _fleetFractionPrice);
    }


    /// @notice Set the maximum number of fleet orders.
    /// @param _maxFleetOrder The maximum number of fleet orders to set.    
    function setMaxFleetOrder(uint256 _maxFleetOrder) external onlyOwner {
        if (_maxFleetOrder <= maxFleetOrder) revert MaxFleetOrderNotIncreased();
        uint256 oldMax = maxFleetOrder;
        maxFleetOrder = _maxFleetOrder;
        emit MaxFleetOrderChanged(oldMax, _maxFleetOrder);
    }


    /// @notice Set the referrer.
    /// @param referrers The addresses to set as referrers.
    function addReferrer(address[] calldata referrers) external onlyOwner {
        // First check all referrers are valid before making any changes
        for (uint256 i = 0; i < referrers.length; i++) {
            if (isReferrer[referrers[i]]) revert AlreadyReferred();
        }

        // If all checks pass, then set the referrers
        for (uint256 i = 0; i < referrers.length; i++) {
            isReferrer[referrers[i]] = true;
        }
    }

    /// @notice Set the whitelist.
    /// @param owners The addresses to set as whitelisted.
    function addWhitelisted(address[] calldata owners) external {
        if (!isReferrer[msg.sender]) revert NotReferrer();
        if (!isCompliant[msg.sender]) revert NotCompliant();
        for (uint256 i = 0; i < owners.length; i++) {
            if (isReferrer[owners[i]]) revert CannotWhitelistReferrer();
            if (isWhitelisted[owners[i]]) revert AlreadyWhitelisted();
        }

        for (uint256 i = 0; i < owners.length; i++) {
            isWhitelisted[owners[i]] = true;
            referral[owners[i]] = msg.sender;
            emit Whitelisted(msg.sender, owners[i]);
        }
    }


    /// @notice Set the compliance.
    /// @param owners The addresses to set as compliant.
    function setCompliance(address[] calldata owners) external onlyOwner {
        for (uint256 i = 0; i < owners.length; i++) {
                if (isCompliant[owners[i]]) revert AlreadyCompliant();
            }

        for (uint256 i = 0; i < owners.length; i++) {
            isCompliant[owners[i]] = true;
        }
    }


    /// @notice Add erc20contract to fleetERC20s.
    /// @param erc20Contract The address of the ERC20 contract.
    function addERC20(address erc20Contract) 
        external
        onlyOwner
    {
        if (erc20Contract == address(0)) revert InvalidTokenAddress();
        if (fleetERC20[erc20Contract]) revert TokenAlreadyAdded();

        fleetERC20[erc20Contract] = true;
        emit ERC20Added(erc20Contract);
    }

    
    /// @notice remove erc20contract from fleetERC20s.
    /// @param erc20Contract The address of the ERC20 contract.
    function removeERC20(address erc20Contract) external onlyOwner {
        if (erc20Contract == address(0)) revert InvalidTokenAddress();
        if (!fleetERC20[erc20Contract]) revert TokenNotAdded();
        
        fleetERC20[erc20Contract] = false;
        emit ERC20Removed(erc20Contract);
    }
    

    /// @notice Pay fee in ERC20.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function payFeeERC20(uint256 fractions, address erc20Contract) internal {
        IERC20 tokenContract = IERC20(erc20Contract);
        uint256 decimals = IERC20Metadata(erc20Contract).decimals();
        
        // Cache fleetFractionPrice in memory
        uint256 price = fleetFractionPrice;
        
        uint256 amount = price * fractions * (10 ** decimals);
        if (tokenContract.balanceOf(msg.sender) < amount) revert NotEnoughTokens();
        tokenContract.safeTransferFrom(msg.sender, address(this), amount);
    }


    /// @notice Check if a token is in the fleetERC20s list.
    /// @param erc20Contract The address of the token to check.
    /// @return bool True if the token is in the list, false otherwise.
    function isTokenValid(address erc20Contract) internal view returns (bool) {
        return fleetERC20[erc20Contract];
    }


    /// @notice Check if a fleet order is owned by an address.
    /// @param owner The address of the owner.
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


    /// @notice Check if a fleet order is owned by an address.
    /// @param owner The address of the owner.
    /// @param id The id of the fleet order to check.
    /// @return bool True if the address is fleet owner false otherwise.
    function isAddressFleetOwner(address owner, uint256 id) internal view returns (bool){
        // If no orders exist for msg.sender, return false immediately.
        if (fleetOwners[id].length == 0) return false;
        
        // Retrieve the stored index for the order id.
        uint256 index = fleetOwnersIndex[id][owner];

        // If the index is out of range, then id is not owned.
        if (index >= fleetOwners[id].length) return false;
        
        // Check that the order at that index matches the given id.
        return fleetOwners[id][index] == owner;
    }


    /// @notice Add a fleet order to the owner.
    /// @param receiver The address of the receiver.
    /// @param id The id of the fleet order to add.
    function addFleetOrder(address receiver, uint256 id) internal {
        uint256[] storage owned = fleetOwned[receiver];
        owned.push(id);
        fleetOwnedIndex[receiver][id] = owned.length - 1;
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


    /// @notice Add a fleet owner.
    /// @param id The id of the fleet order to add.
    /// @param receiver The address of the owner.
    function addFleetOwner(address receiver, uint256 id) internal {
        address[] storage owners = fleetOwners[id];
        owners.push(receiver);
        fleetOwnersIndex[id][receiver] = owners.length - 1;
    }


    /// @notice Remove a fleet owner.
    /// @param id The id of the fleet order to remove.
    /// @param receiver The address of the owner.
    function removeFleetOwner(uint256 id, address receiver) internal {
        // Get the index of the orderId in the owner's fleetOwned array.
        uint256 indexToRemove = fleetOwnersIndex[id][receiver];
        uint256 lastIndex = fleetOwners[id].length - 1;

        // If the order being removed is not the last one, swap it with the last element.
        if (indexToRemove != lastIndex) {
            address lastOwner = fleetOwners[id][lastIndex];
            fleetOwners[id][indexToRemove] = lastOwner;
            // Update the index mapping for the swapped order.
            fleetOwnersIndex[id][lastOwner] = indexToRemove;
        }
        
        // Remove the last element and delete the mapping entry for the removed order.
        fleetOwners[id].pop();
        delete fleetOwnersIndex[id][receiver];
    }


    /// @notice Handle a full fleet order.
    /// @param erc20Contract The address of the ERC20 contract.
    function handleFullFleetOrder(address erc20Contract) internal returns (uint256) {
        //pay fee
        payFeeERC20(MAX_FLEET_FRACTION, erc20Contract);
        // id counter
        totalFleet++;
        totalFractions[totalFleet] = 1;
        // set status
        setFleetOrderStatus(totalFleet, INIT);
        emit FleetOrderStatusChanged(totalFleet, INIT);
        // add fleet order ID to fleetOwned
        addFleetOrder(msg.sender, totalFleet);
        // add fleet owner
        addFleetOwner(msg.sender, totalFleet);
        // mint fractions
        _mint(msg.sender, totalFleet, 1);  
        return totalFleet;
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
        fleetFractioned[lastFleetFractionID] = true;
        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
        // set status
        setFleetOrderStatus(lastFleetFractionID, INIT);
        emit FleetOrderStatusChanged(lastFleetFractionID, INIT);
        // add fleet order ID to fleetOwned
        addFleetOrder(msg.sender, lastFleetFractionID);
        // add fleet owner
        addFleetOwner(msg.sender, lastFleetFractionID);
        // mint fractions
        _mint(msg.sender, lastFleetFractionID, fractions);
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
        // add fleet owner if not already an owner
        if (!isAddressFleetOwner(msg.sender, lastFleetFractionID)) {
            addFleetOwner(msg.sender, lastFleetFractionID);
        }
        // mint fractions
        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
        _mint(msg.sender, lastFleetFractionID, fractions);
    }

   
    /// @notice Handle a fractional fleet order overflow.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    /// @param fractionsLeft The number of fractions left.
    function handleFractionsFleetOrderOverflow(uint256 fractions, address erc20Contract, uint256 fractionsLeft) internal returns (uint256[] memory, uint256[] memory) {
        //pay fee
        payFeeERC20(fractions, erc20Contract);

        // add fleet order ID to fleetOwned
        if (!isFleetOwned(msg.sender, lastFleetFractionID)) {
            addFleetOrder(msg.sender, lastFleetFractionID);
        }
        // add fleet owner if not already an owner
        if (!isAddressFleetOwner(msg.sender, lastFleetFractionID)) {
            addFleetOwner(msg.sender, lastFleetFractionID);
        }
        
        uint256[] memory ids = new uint256[](2);
        uint256[] memory fractionals = new uint256[](2);
        // check overflow value 
        uint256 overflowFractions = fractions - fractionsLeft;

        // mint what is posible then...
        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractionsLeft;
        _mint(msg.sender, lastFleetFractionID, fractionsLeft);
        ids[0] = lastFleetFractionID;
        fractionals[0] = fractionsLeft;

        // id counter
        totalFleet++;
        lastFleetFractionID = totalFleet;
        fleetFractioned[lastFleetFractionID] = true;
        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + overflowFractions;
        // set status
        setFleetOrderStatus(lastFleetFractionID, INIT);
        emit FleetOrderStatusChanged(lastFleetFractionID, INIT);
        // add fleet order ID to fleetOwned
        addFleetOrder(msg.sender, lastFleetFractionID);
        // add fleet owner
        addFleetOwner(msg.sender, lastFleetFractionID);
        //...mint overflow
        _mint(msg.sender, lastFleetFractionID, overflowFractions);
        ids[1] = lastFleetFractionID;
        fractionals[1] = overflowFractions;

        return (ids, fractionals);
    }
    

    /// @notice Order multiple fleet orders.
    /// @param amount The number of fleet orders to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function orderFleet(uint256 amount, address erc20Contract, address referrer) external nonReentrant whenNotPaused {
        if (fleetOwned[msg.sender].length + amount > MAX_FLEET_ORDER_PER_ADDRESS) revert MaxFleetOrderPerAddressExceeded();
        if (amount > MAX_ORDER_MULTIPLE_FLEET) revert MaxOrderMultipleFleetExceeded();
        if (amount < 1) revert InvalidAmount();
        if (!isTokenValid(erc20Contract)) revert TokenNotAccepted();
        if (erc20Contract == address(0)) revert InvalidTokenAddress();
        if (totalFleet + amount > maxFleetOrder) revert MaxFleetOrderExceeded();

        if (referrer == address(0)) revert InvalidReferrer();
        if (!isReferrer[referrer]) revert NotReferrer();
        if (!isWhitelisted[msg.sender]) revert NotWhitelisted();
        if (!isCompliant[msg.sender]) revert NotCompliant();
        
        uint256[] memory ids = new uint256[](amount);

        for (uint256 i = 0; i < amount; i++) {
            // handle full fleet order
            ids[i] = handleFullFleetOrder(erc20Contract);
        }
        emit FleetOrdered(ids, msg.sender, amount);

        uint256 shares = amount * MAX_FLEET_FRACTION;
        referrerPoolShares[referrer] += shares;
        referralPoolShares[msg.sender] += shares;
        emit Referrered(referrer, msg.sender, shares);
        
    }


    /// @notice Order a fleet onchain.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function orderFleetFraction(uint256 fractions, address erc20Contract, address referrer) external nonReentrant whenNotPaused {
        // Input validation
        if (!isTokenValid(erc20Contract)) revert TokenNotAccepted();
        if (erc20Contract == address(0)) revert InvalidTokenAddress();
        if (fractions < MIN_FLEET_FRACTION) revert InvalidFractionAmount();
        if (fractions >= MAX_FLEET_FRACTION) revert FractionExceedsMax();

        if (referrer == address(0)) revert InvalidReferrer();
        if (!isReferrer[referrer]) revert NotReferrer();
        if (!isWhitelisted[msg.sender]) revert NotWhitelisted();
        if (!isCompliant[msg.sender]) revert NotCompliant();

        // if first mint ie no last fleetFraction ID we create one
        if (lastFleetFractionID < 1) {
            handleInitialFractionsFleetOrder(fractions, erc20Contract);
            emit FleetFractionOrdered(lastFleetFractionID, msg.sender, fractions);

            // add to referral pool
            referrerPoolShares[referrer] += fractions;
            referralPoolShares[msg.sender] += fractions;
            emit Referrered(referrer, msg.sender, fractions);
        }
        // if not first mint
        else {
            // check fraction left of last token id
            uint256 fractionsLeft = MAX_FLEET_FRACTION - totalFractions[lastFleetFractionID];

            // if fractions Left is zero ie last fraction quota completely filled
            if (fractionsLeft < 1) {
                if (fleetOwned[msg.sender].length + 1 > MAX_FLEET_ORDER_PER_ADDRESS) revert MaxFleetOrderPerAddressExceeded();
                if (totalFleet + 1 > maxFleetOrder) revert MaxFleetOrderExceeded();
                handleInitialFractionsFleetOrder(fractions, erc20Contract);
                emit FleetFractionOrdered(lastFleetFractionID, msg.sender, fractions);

                // add to referral pool
                referrerPoolShares[referrer] += fractions;
                referralPoolShares[msg.sender] += fractions;
                emit Referrered(referrer, msg.sender, fractions);
            } else {
                // if requested fractions fit in remaining space
                if (fractions <= fractionsLeft) {
                    handleAdditionalFractionsFleetOrder(fractions, erc20Contract);
                    emit FleetFractionOrdered(lastFleetFractionID, msg.sender, fractions);

                    // add to referral pool
                    referrerPoolShares[referrer] += fractions;
                    referralPoolShares[msg.sender] += fractions;
                    emit Referrered(referrer, msg.sender, fractions);
                }
                // if requested fractions exceed remaining space, split into two orders
                else {
                    if (fleetOwned[msg.sender].length + 1 > MAX_FLEET_ORDER_PER_ADDRESS) revert MaxFleetOrderPerAddressExceeded();
                    if (totalFleet + 1 > maxFleetOrder) revert MaxFleetOrderExceeded();
                    (uint256[] memory ids, uint256[] memory fractionals) = handleFractionsFleetOrderOverflow(fractions, erc20Contract, fractionsLeft);
                    emit FleetFractionOverflowOrdered(ids, msg.sender, fractionals);

                    // add to referral pool
                    referrerPoolShares[referrer] += fractions;
                    referralPoolShares[msg.sender] += fractions;
                    emit Referrered(referrer, msg.sender, fractions);
                }
            }
        }
    }


    /// @notice Check if a status value is valid
    /// @param status The status to check
    /// @return bool True if the status is valid
    function isValidStatus(uint256 status) internal pure returns (bool) {
        // Use bitwise operations for faster validation
        return status > 0 && status <= TRANSFERRED && (status & (status - 1)) == 0;
    }


    /// @notice Check if a state transition is valid
    /// @param currentStatus The current status
    /// @param newStatus The new status to transition to
    /// @return bool True if the transition is valid
    function isValidTransition(uint256 currentStatus, uint256 newStatus) internal pure returns (bool) {
        if (currentStatus == INIT) return newStatus == CREATED;
        if (currentStatus == CREATED) return newStatus == SHIPPED;
        if (currentStatus == SHIPPED) return newStatus == ARRIVED;
        if (currentStatus == ARRIVED) return newStatus == CLEARED;
        if (currentStatus == CLEARED) return newStatus == REGISTERED;
        if (currentStatus == REGISTERED) return newStatus == ASSIGNED;
        if (currentStatus == ASSIGNED) return newStatus == TRANSFERRED;
        return false;
    }


    /// @notice Check for duplicate IDs in an array
    /// @param ids The array of IDs to check
    /// @return bool True if there are no duplicates
    function hasNoDuplicates(uint256[] memory ids) internal pure returns (bool) {
        for (uint256 i = 0; i < ids.length; i++) {
            for (uint256 j = i + 1; j < ids.length; j++) {
                if (ids[i] == ids[j]) return false;
            }
        }
        return true;
    }


    /// @notice Validate all status transitions in bulk
    /// @param ids The array of IDs to validate
    /// @param status The new status to validate against
    /// @return bool True if all transitions are valid
    function validateBulkTransitions(uint256[] memory ids, uint256 status) internal view returns (bool) {
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            if (id == 0) return false;
            if (id > totalFleet) return false;
            
            uint256 currentStatus = fleetOrderStatus[id];
            if (currentStatus != 0 && !isValidTransition(currentStatus, status)) {
                return false;
            }
        }
        return true;
    }


    /// @notice Set the status of a fleet order
    /// @param id The id of the fleet order to set the status for
    /// @param status The new status to set
    function setFleetOrderStatus(uint256 id, uint256 status) internal {
        fleetOrderStatus[id] = status;
        emit FleetOrderStatusChanged(id, status);
    }


    /// @notice Set the status of multiple fleet orders
    /// @param ids The ids of the fleet orders to set the status for
    /// @param status The new status to set
    function setBulkFleetOrderStatus(uint256[] memory ids, uint256 status) external onlyOwner {
        // Early checks (cheap)
        if (ids.length == 0) revert InvalidAmount();
        if (ids.length > MAX_BULK_UPDATE) revert BulkUpdateLimitExceeded();
        if (!hasNoDuplicates(ids)) revert DuplicateIds();
        if (!isValidStatus(status)) revert InvalidStatus();
        
        // Validate all transitions before making any changes
        if (!validateBulkTransitions(ids, status)) revert InvalidStateTransition();

        // Now we can safely update all statuses
        for (uint256 i = 0; i < ids.length; i++) {
            setFleetOrderStatus(ids[i], status);
        }
    }


    /// @notice Get the current status of a fleet order
    /// @param id The id of the fleet order to get the status for
    /// @return string The human-readable status string
    function getFleetOrderStatus(uint256 id) public view returns (string memory) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        uint256 status = fleetOrderStatus[id];
        
        if (status == INIT) return "Initialized";
        if (status == CREATED) return "Created";
        if (status == SHIPPED) return "Shipped";
        if (status == ARRIVED) return "Arrived";
        if (status == CLEARED) return "Cleared";
        if (status == REGISTERED) return "Registered";
        if (status == ASSIGNED) return "Assigned";
        if (status == TRANSFERRED) return "Transferred";
        
        revert InvalidStatus();
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
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        if (fleetOwned[receiver].length >= MAX_FLEET_ORDER_PER_ADDRESS) revert MaxFleetOrderPerAddressExceeded();
        if (balanceOf[msg.sender][id] < amount) revert InsufficientBalance();
        
        balanceOf[msg.sender][id] -= amount;
        if (balanceOf[msg.sender][id] == 0) {
            removeFleetOrder(id, msg.sender);
            removeFleetOwner(id, msg.sender);
        }

        balanceOf[receiver][id] += amount;
        if (!isFleetOwned(receiver, id)) {
            addFleetOrder(receiver, id);
        }
        if (!isAddressFleetOwner(receiver, id)){
            addFleetOwner(receiver, id);
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
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        if (fleetOwned[receiver].length >= MAX_FLEET_ORDER_PER_ADDRESS) revert MaxFleetOrderPerAddressExceeded();

        if (msg.sender != sender && !isOperator[sender][msg.sender]) {
            uint256 allowed = allowance[sender][msg.sender][id];
            if (allowed != type(uint256).max) allowance[sender][msg.sender][id] = allowed - amount;
        }

        if (balanceOf[sender][id] < amount) revert InsufficientBalance();
        balanceOf[sender][id] -= amount;
        if (balanceOf[sender][id] == 0) {
            removeFleetOrder(id, sender);
            removeFleetOwner(id, sender);
        }

        balanceOf[receiver][id] += amount;
        if (!isFleetOwned(receiver, id)) {
            addFleetOrder(receiver, id);
        }
        if (!isAddressFleetOwner(receiver, id)){
            addFleetOwner(receiver, id);
        }
        
        emit Transfer(msg.sender, sender, receiver, id, amount);
        return true;
    }


    /// @notice Withdraw sales from fleet order book.
    /// @param token The address of the ERC20 contract.
    /// @param to The address to send the sales to.
    function withdrawFleetOrderSales(address token, address to) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidTokenAddress();
        IERC20 tokenContract = IERC20(token);
        uint256 amount = tokenContract.balanceOf(address(this));
        if (amount == 0) revert NotEnoughTokens();
        tokenContract.safeTransfer(to, amount);
        emit FleetSalesWithdrawn(token, to, amount);
    }


    receive() external payable { revert NoNativeTokenAccepted(); }
    fallback() external payable { revert NoNativeTokenAccepted(); }


}

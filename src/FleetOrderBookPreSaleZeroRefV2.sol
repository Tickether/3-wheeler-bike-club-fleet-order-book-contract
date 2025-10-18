// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


/// @dev Interface imports
import { IERC6909TokenSupply } from "./interfaces/IERC6909TokenSupply.sol";
import { IFleetOrderYield } from "./interfaces/IFleetOrderYield.sol";

/// @dev Solmate imports
import { ERC6909 } from "solmate/tokens/ERC6909.sol";
//import { ERC6909 } from  "https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC6909.sol";

/// @dev OpenZeppelin utils imports
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev OpenZeppelin access imports
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";



/// @title 3wb.club fleet order book V2.0
/// @notice Manages pre-orders for fractional and full investments in 3-wheelers
/// @notice Implements role-based access control for enhanced security
/// @notice Implements unique initial and return rate for each fleet order
/// @author geeloko.eth
/// 
/// @dev Role-based Access Control System:
/// - DEFAULT_ADMIN_ROLE: Can grant/revoke all other roles, highest privilege
/// - SUPER_ADMIN_ROLE: Can pause/unpause, set prices, max orders, add/remove ERC20s, update fleet status
/// - COMPLIANCE_ROLE: Can set compliance status for users
/// - WITHDRAWAL_ROLE: Can withdraw sales from the contract
/// 
/// @dev Security Benefits:
/// - Reduces risk of compromising the deployer wallet
/// - Allows delegation of specific functions to different admin addresses
/// - Provides granular control over different aspects of the contract
/// - Enables multi-signature or DAO governance for critical functions



contract FleetOrderBookPreSale is IERC6909TokenSupply, ERC6909, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Strings for uint256;
    
    /// @notice Role definitions
    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant WITHDRAWAL_ROLE = keccak256("WITHDRAWAL_ROLE");


    /// @notice The fleet order yield contract
    IFleetOrderYield public fleetOrderYieldContract;


    /// @notice Total supply of a ids representing fleet orders.
    uint256 public totalFleet;
    /// @notice Last fleet fraction ID.
    uint256 public lastFleetFractionID;    
    /// @notice Total number of fleet orders in a container.
    uint256 public totalFleetOrderPerContainer;
    /// @notice Maximum number of fleet orders in a container.
    uint256 public maxFleetOrderPerContainer;
    /// @notice Total number of fleet container orders.
    uint256 public totalFleetContainerOrder;
    /// @notice  Price per fleet fraction in USD.
    uint256 public fleetFractionPrice;
    /// @notice  Protocol expected value for fleet in USD.
    uint256 public fleetProtocolExpectedValue;
    /// @notice  Liquidity provider expected value for fleet in USD.
    uint256 public fleetLiquidityProviderExpectedValue;
    /// @notice  Lock period for fleet in weeks.
    uint256 public fleetLockPeriod;
    /// @notice  Off ramp service fee for fleet in percentage added to USD price. eg. 100 = 1% , 1000 = 10% , 10000 = 100%
    uint256 public offRampServiceFee; 


    /// @notice State constants - each state is a power of 2 (bit position)
    uint256 constant INIT = 1 << 0;         // 0000001
    uint256 constant SHIPPED = 1 << 1;      // 0000010
    uint256 constant ARRIVED = 1 << 2;      // 0000100
    uint256 constant CLEARED = 1 << 3;      // 0001000
    uint256 constant REGISTERED = 1 << 4;   // 0010000
    uint256 constant ASSIGNED = 1 << 5;     // 0100000
    uint256 constant TRANSFERRED = 1 << 6;  // 1000000


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
    

    /// @notice check if ERC20 is accepted for fleet orders
    mapping(address => bool) public fleetERC20;

    /// @notice Mapping to store the operator of each 3-wheeler fleet order
    mapping(uint256 => address[]) private fleetOperators;
    /// @notice Mapping to store the operator of each 3-wheeler fleet order
    mapping(address => uint256[]) private fleetOperated;


    /// @notice Mapping to store the price and inital value of each 3-wheeler fleet order
    mapping(uint256 => uint256) private fleetInitialValuePerOrder;
    /// @notice Mapping to store the expected protocol return for each 3-wheeler fleet order
    mapping(uint256 => uint256) private fleetProtocolExpectedValuePerOrder;
    /// @notice Mapping to store the expected liquidity provider return for each 3-wheeler fleet order
    mapping(uint256 => uint256) private fleetLiquidityProviderExpectedValuePerOrder;
    /// @notice Mapping to store the lock period for each 3-wheeler fleet order
    mapping(uint256 => uint256) private fleetLockPeriodPerOrder;
    /// @notice Mapping to store the vehicle identification number for each 3-wheeler fleet order
    mapping(uint256 => string) private fleetVehicleIdentificationNumberPerOrder;
    /// @notice Mapping to store the license plate number for each 3-wheeler fleet order
    mapping(uint256 => string) private fleetLicensePlateNumberPerOrder;


    /// @notice Mapping to store the IRL fulfillment state of each 3-wheeler fleet order
    mapping(uint256 => uint256) private fleetOrderStatus;
    /// @notice owner => list of fleet order IDs
    mapping(address => uint256[]) private fleetOwned;
    /// @notice fleet order ID => list of owners
    mapping(uint256 => address[]) private fleetOwners;
    /// @notice checks if a token representing a 3-wheeler is fractioned.
    mapping(uint256 => bool) private fleetFractioned;
    /// @notice Total fractions of a token representing a 3-wheeler.
    mapping(uint256 => uint256) private totalFractions;
    /// @notice Total fleet orders per container.
    mapping(uint256 => uint256) private totalFleetPerContainer;
    /// @notice Mapping to store the tracking of each 3-wheeler fleet order per container
    mapping(uint256 => string) private trackingPerContainer;
    /// @notice tracking fleet order index for each owner
    mapping(address => mapping(uint256 => uint256)) private fleetOwnedIndex;
    /// @notice tracking owners index for each fleet order
    mapping(uint256 => mapping(address => uint256)) private fleetOwnersIndex;
    /// @notice tracking fleet order index for each operator
    mapping(address => mapping(uint256 => uint256)) private fleetOperatedIndex;
    /// @notice tracking operators index for each fleet order
    mapping(uint256 => mapping(address => uint256)) private fleetOperatorsIndex;
    

    /*...........................................................................*/
    // pool tracking(tracking user total fleet orders in pre-sale) + compliance  
    /*...........................................................................*/
   
    /// @notice Whether a wallet is compliant.
    mapping(address => bool) public isCompliant;
    /// @notice Mapping of individual users to total pool shares (total fleet orders).
    mapping(address => uint256) public poolShares;
    


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
    /// @notice Event emitted when a fleet order status changes.
    event FleetOrderStatusChanged(uint256 indexed id, uint256 status);
    /// @notice Event emitted when the maximum fleet orders in a container is changed.
    event MaxFleetOrderPerContainerChanged(uint256 oldMax, uint256 newMax);

    /// @notice Error messages
    error InvalidStatus();
    error InvalidStateTransition();
    error DuplicateIds();
    error BulkUpdateLimitExceeded();
    error InvalidId();
    error IdDoesNotExist();
    error InvalidAddress();
    error TokenNotAccepted();
    error InsufficientBalance();
    error MaxFleetOrderPerContainerExceeded();
    error MaxFleetOrderPerContainerNotReached();
    error MaxOrderMultipleFleetExceeded();
    error MaxFleetOrderPerAddressExceeded();
    error InvalidFractionAmount();
    error FractionExceedsMax();
    error NotEnoughTokens();
    error InvalidAmount();
    error NoNativeTokenAccepted();
    error InvalidPrice();
    error MaxFleetOrderPerContainerCannotBeZero();
    error MaxFleetOrderPerContainerCannotBeLessThanTotal();
    error TokenAlreadyAdded();
    error TokenNotAdded();
    error NotCompliant();
    error AlreadyCompliant();
    error CannotChangeValueDuringOpenRound();
    error OperatorAlreadyAssigned();


    constructor() AccessControl() {
        _pause();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SUPER_ADMIN_ROLE, msg.sender);
    }

    /// @notice Override supportsInterface to handle multiple inheritance
    /// @param interfaceId The interface ID to check
    /// @return bool True if the interface is supported
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC6909) returns (bool) {
        return AccessControl.supportsInterface(interfaceId) || ERC6909.supportsInterface(interfaceId);
    }


    /// @notice Pause the contract 
    function pause() external onlyRole(SUPER_ADMIN_ROLE) {
        _pause();
    }


    /// @notice Unpause the contract
    function unpause() external onlyRole(SUPER_ADMIN_ROLE) {
        _unpause();
    }


    /// @notice Set the fleet fraction price.
    /// @param _fleetFractionPrice The price to set.
    function setFleetFractionPrice(uint256 _fleetFractionPrice) external onlyRole(SUPER_ADMIN_ROLE) {
        if (_fleetFractionPrice == 0) revert InvalidPrice();
        if (totalFleetOrderPerContainer != 0) revert CannotChangeValueDuringOpenRound();
        uint256 oldPrice = fleetFractionPrice;
        fleetFractionPrice = _fleetFractionPrice;
        emit FleetFractionPriceChanged(oldPrice, _fleetFractionPrice);
    }


    /// @notice Set the off ramp service fee.
    /// @param _offRampServiceFee The off ramp service fee to set.
    function setOffRampServiceFee(uint256 _offRampServiceFee) external onlyRole(SUPER_ADMIN_ROLE) {
        if (_offRampServiceFee == 0) revert InvalidPrice();
        if (totalFleetOrderPerContainer != 0) revert CannotChangeValueDuringOpenRound();
        offRampServiceFee = _offRampServiceFee;
    }


    /// @notice Set the fleet expected rate.
    /// @param _fleetProtocolExpectedValue The expected value to set.
    /// @param _fleetLiquidityProviderExpectedValue The expected value to set.
    /// @param _fleetLockPeriod The lock period to set.
    function setFleetExpectedValuePlusLockPeriod(uint256 _fleetProtocolExpectedValue, uint256 _fleetLiquidityProviderExpectedValue, uint256 _fleetLockPeriod) external onlyRole(SUPER_ADMIN_ROLE) {
        if (totalFleetOrderPerContainer != 0) revert CannotChangeValueDuringOpenRound();
        fleetProtocolExpectedValue = _fleetProtocolExpectedValue;
        fleetLiquidityProviderExpectedValue = _fleetLiquidityProviderExpectedValue;
        fleetLockPeriod = _fleetLockPeriod;
    }


    /// @notice Set the fleet initial value.
    /// @param _fleetInitialValuePerOrder The value to set.
    function setFleetInitialValuePerOrder(uint256 _fleetInitialValuePerOrder, uint256 id) internal {
        fleetInitialValuePerOrder[id] = _fleetInitialValuePerOrder;
    }


    /// @notice Set the fleet expected rate.
    /// @param _fleetProtocolExpectedValuePerOrder The rate to set.
    function setFleetProtocolExpectedValuePerOrder(uint256 _fleetProtocolExpectedValuePerOrder, uint256 id) internal {
        fleetProtocolExpectedValuePerOrder[id] = _fleetProtocolExpectedValuePerOrder;
    }


    /// @notice Set the fleet expected rate.
    /// @param _fleetLiquidityProviderExpectedValuePerOrder The rate to set.
    function setFleetLiquidityProviderExpectedValuePerOrder(uint256 _fleetLiquidityProviderExpectedValuePerOrder, uint256 id) internal {
        fleetLiquidityProviderExpectedValuePerOrder[id] = _fleetLiquidityProviderExpectedValuePerOrder;
    }


    /// @notice Set the fleet lock period.
    /// @param _fleetLockPeriod The lock period to set.
    function setFleetLockPeriodPerOrder(uint256 _fleetLockPeriod, uint256 id) internal {
        fleetLockPeriodPerOrder[id] = _fleetLockPeriod;
    }



    /// @notice Set the fleet vehicle identification number.
    /// @param _fleetVehicleIdentificationNumber The vehicle identification number to set.
    function setFleetVehicleIdentificationNumberPerOrder(string memory _fleetVehicleIdentificationNumber, uint256 id) internal {
        fleetVehicleIdentificationNumberPerOrder[id] = _fleetVehicleIdentificationNumber;
    }


    /// @notice Set the fleet license plate number.
    /// @param _fleetLicensePlateNumber The license plate number to set.
    function setFleetLicensePlateNumberPerOrder(string memory _fleetLicensePlateNumber, uint256 id) internal {
        fleetLicensePlateNumberPerOrder[id] = _fleetLicensePlateNumber;
    }


    /// @notice Set tracking per container.
    /// @param _trackingPerContainer The tracking per container to set.
    function setTrackingPerContainer(string memory _trackingPerContainer, uint256 id) internal {
        trackingPerContainer[id] = _trackingPerContainer;
    }


    /// @notice Set the maximum number of fleet orders.
    /// @param _maxFleetOrderPerContainer The maximum number of fleet orders in a container to set.    
    function setMaxFleetOrderPerContainer(uint256 _maxFleetOrderPerContainer) external onlyRole(SUPER_ADMIN_ROLE) {
        if (_maxFleetOrderPerContainer == 0) revert MaxFleetOrderPerContainerCannotBeZero();
        if (_maxFleetOrderPerContainer <= totalFleetOrderPerContainer) revert MaxFleetOrderPerContainerCannotBeLessThanTotal();
        if (totalFleetOrderPerContainer != 0) revert CannotChangeValueDuringOpenRound();
        uint256 oldMax = maxFleetOrderPerContainer;
        maxFleetOrderPerContainer = _maxFleetOrderPerContainer;
        emit MaxFleetOrderPerContainerChanged(oldMax, _maxFleetOrderPerContainer);
    }


    function setFleetOrderYieldContract(address _fleetOrderYieldContract) external onlyRole(SUPER_ADMIN_ROLE) {
        if (_fleetOrderYieldContract == address(0)) revert InvalidAddress();
        fleetOrderYieldContract = IFleetOrderYield(_fleetOrderYieldContract);
    }


    /// @notice Set the compliance.
    /// @param owners The addresses to set as compliant.
    function setCompliance(address[] calldata owners) external onlyRole(COMPLIANCE_ROLE) {
        if (owners.length == 0) revert InvalidAmount();
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
        onlyRole(SUPER_ADMIN_ROLE)
    {
        if (erc20Contract == address(0)) revert InvalidAddress();
        if (fleetERC20[erc20Contract]) revert TokenAlreadyAdded();

        fleetERC20[erc20Contract] = true;
        emit ERC20Added(erc20Contract);
    }

    
    /// @notice remove erc20contract from fleetERC20s.
    /// @param erc20Contract The address of the ERC20 contract.
    function removeERC20(address erc20Contract) external onlyRole(SUPER_ADMIN_ROLE) {
        if (erc20Contract == address(0)) revert InvalidAddress();
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
        // If no orders exist for owner, return false immediately.
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
        // If no orders exist for receiver, return false immediately.
        if (fleetOwners[id].length == 0) return false;
        
        // Retrieve the stored index for the order id.
        uint256 index = fleetOwnersIndex[id][owner];

        // If the index is out of range, then id is not owned.
        if (index >= fleetOwners[id].length) return false;
        
        // Check that the order at that index matches the given id.
        return fleetOwners[id][index] == owner;
    }
    

    /// @notice Check if a fleet order is operated by an address.
    /// @param operator The address of the operator.
    /// @param id The id of the fleet order to check.
    /// @return bool True if the fleet order is operated by the address, false otherwise.
    function isAddressFleetOperator(address operator, uint256 id) internal view returns (bool) {
        // If no orders exist for receiver, return false immediately.
        if (fleetOperators[id].length == 0) return false;
        
        // Retrieve the stored index for the order id.
        uint256 index = fleetOperatorsIndex[id][operator];

        // If the index is out of range, then id is not owned.
        if (index >= fleetOperators[id].length) return false;
        
        // Check that the order at that index matches the given id.
        return fleetOperators[id][index] == operator;
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


    /// @notice Add a fleet order to the owner.
    /// @param operator The address of the operator.
    /// @param id The id of the fleet order to add.
    function addFleetOperated(address operator, uint256 id) internal {
        uint256[] storage owned = fleetOperated[operator];
        owned.push(id);
        fleetOperatedIndex[operator][id] = owned.length - 1;
    }


    /// @notice Add a fleet operator.
    /// @param operator The address of the operator.
    /// @param id The id of the fleet order to add.
    function addFleetOperator(address operator, uint256 id) internal {
        address[] storage operators = fleetOperators[id];
        operators.push(operator);
        fleetOperatorsIndex[id][operator] = operators.length - 1;
    }



    /// @notice Handle a full fleet order.
    /// @param erc20Contract The address of the ERC20 contract.
    function handleFullFleetOrder(address erc20Contract, address receiver) internal returns (uint256) {
        //pay fee
        payFeeERC20(MAX_FLEET_FRACTION, erc20Contract);
        // id counter
        totalFleet++;
        totalFractions[totalFleet] = 1;
        // container counter
        totalFleetOrderPerContainer++;

        
        // set initial value
        setFleetInitialValuePerOrder(MAX_FLEET_FRACTION * fleetFractionPrice, totalFleet);
        // set protocol expected rate
        setFleetProtocolExpectedValuePerOrder(fleetProtocolExpectedValue, totalFleet);
        // set liquidity provider expected rate
        setFleetLiquidityProviderExpectedValuePerOrder(fleetLiquidityProviderExpectedValue, totalFleet);
        // set lock period
        setFleetLockPeriodPerOrder(fleetLockPeriod, totalFleet);


        // set status
        setFleetOrderStatus(totalFleet, INIT);
        emit FleetOrderStatusChanged(totalFleet, INIT);
        // add fleet order ID to fleetOwned
        addFleetOrder(receiver, totalFleet);
        // add fleet owner
        addFleetOwner(receiver, totalFleet);
        // mint fractions
        _mint(receiver, totalFleet, 1);  
        return totalFleet;
    }


    /// @notice Handle an initial fractional fleet order.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function handleInitialFractionsFleetOrder(uint256 fractions, address erc20Contract, address receiver) internal {
        // pay fee
        payFeeERC20(fractions, erc20Contract);
        // id counter
        totalFleet++;
        lastFleetFractionID = totalFleet;
        fleetFractioned[lastFleetFractionID] = true;
        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
        // container counter
        totalFleetOrderPerContainer++;

        
        // set initial value
        setFleetInitialValuePerOrder(fractions * fleetFractionPrice, totalFleet);
        // set protocol expected rate
        setFleetProtocolExpectedValuePerOrder(fleetProtocolExpectedValue, totalFleet);
        // set liquidity provider expected rate
        setFleetLiquidityProviderExpectedValuePerOrder(fleetLiquidityProviderExpectedValue, totalFleet);
        // set lock period
        setFleetLockPeriodPerOrder(fleetLockPeriod, totalFleet);

        // set status
        setFleetOrderStatus(lastFleetFractionID, INIT);
        emit FleetOrderStatusChanged(lastFleetFractionID, INIT);
        // add fleet order ID to fleetOwned
        addFleetOrder(receiver, lastFleetFractionID);
        // add fleet owner
        addFleetOwner(receiver, lastFleetFractionID);
        // mint fractions
        _mint(receiver, lastFleetFractionID, fractions);
    }
    

    /// @notice Handle an additional fractional fleet order.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function handleAdditionalFractionsFleetOrder(uint256 fractions, address erc20Contract, address receiver) internal {
        //pay fee
        payFeeERC20(fractions, erc20Contract);
        // add fleet order ID to fleetOwned
        if (!isFleetOwned(receiver, lastFleetFractionID)) {
            addFleetOrder(receiver, lastFleetFractionID);
        }
        // add fleet owner if not already an owner
        if (!isAddressFleetOwner(receiver, lastFleetFractionID)) {
            addFleetOwner(receiver, lastFleetFractionID);
        }
        // mint fractions
        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractions;
        _mint(receiver, lastFleetFractionID, fractions);
    }

   
    /// @notice Handle a fractional fleet order overflow.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    /// @param fractionsLeft The number of fractions left.
    function handleFractionsFleetOrderOverflow(uint256 fractions, address erc20Contract, uint256 fractionsLeft, address receiver) internal returns (uint256[] memory, uint256[] memory) {
        //pay fee
        payFeeERC20(fractions, erc20Contract);

        // add fleet order ID to fleetOwned
        if (!isFleetOwned(receiver, lastFleetFractionID)) {
            addFleetOrder(receiver, lastFleetFractionID);
        }
        // add fleet owner if not already an owner
        if (!isAddressFleetOwner(receiver, lastFleetFractionID)) {
            addFleetOwner(receiver, lastFleetFractionID);
        }
        
        uint256[] memory ids = new uint256[](2);
        uint256[] memory fractionals = new uint256[](2);
        // check overflow value 
        uint256 overflowFractions = fractions - fractionsLeft;

        // mint what is posible then...
        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + fractionsLeft;
        _mint(receiver, lastFleetFractionID, fractionsLeft);
        ids[0] = lastFleetFractionID;
        fractionals[0] = fractionsLeft;

        // id counter
        totalFleet++;
        lastFleetFractionID = totalFleet;
        fleetFractioned[lastFleetFractionID] = true;
        totalFractions[lastFleetFractionID] = totalFractions[lastFleetFractionID] + overflowFractions;
        // container counter
        totalFleetOrderPerContainer++;

        
        // set initial value
        setFleetInitialValuePerOrder(fractions * fleetFractionPrice, totalFleet);
        // set protocol expected rate
        setFleetProtocolExpectedValuePerOrder(fleetProtocolExpectedValue, totalFleet);
        // set liquidity provider expected rate
        setFleetLiquidityProviderExpectedValuePerOrder(fleetLiquidityProviderExpectedValue, totalFleet);
        // set lock period
        setFleetLockPeriodPerOrder(fleetLockPeriod, totalFleet);


        // set status
        setFleetOrderStatus(lastFleetFractionID, INIT);
        emit FleetOrderStatusChanged(lastFleetFractionID, INIT);
        // add fleet order ID to fleetOwned
        addFleetOrder(receiver, lastFleetFractionID);
        // add fleet owner
        addFleetOwner(receiver, lastFleetFractionID);
        //...mint overflow
        _mint(receiver, lastFleetFractionID, overflowFractions);
        ids[1] = lastFleetFractionID;
        fractionals[1] = overflowFractions;

        return (ids, fractionals);
    }
    

    /// @notice Order multiple fleet orders.
    /// @param amount The number of fleet orders to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function orderFleet(uint256 amount, address erc20Contract, address receiver) external nonReentrant whenNotPaused {
        // value validation
        if (fleetFractionPrice == 0) revert InvalidAmount();
        if (fleetProtocolExpectedValue == 0) revert InvalidAmount();
        if (fleetLiquidityProviderExpectedValue == 0) revert InvalidAmount();
        if (fleetLockPeriod == 0) revert InvalidAmount();
        
        // input validation
        if (fleetOwned[receiver].length + amount > MAX_FLEET_ORDER_PER_ADDRESS) revert MaxFleetOrderPerAddressExceeded();
        if (amount > MAX_ORDER_MULTIPLE_FLEET) revert MaxOrderMultipleFleetExceeded();
        if (amount < 1) revert InvalidAmount();
        if (!isTokenValid(erc20Contract)) revert TokenNotAccepted();
        if (erc20Contract == address(0)) revert InvalidAddress();
        if (totalFleetOrderPerContainer + amount > maxFleetOrderPerContainer) revert MaxFleetOrderPerContainerExceeded();

        if (!isCompliant[receiver]) revert NotCompliant();
        
        uint256[] memory ids = new uint256[](amount);

        for (uint256 i = 0; i < amount; i++) {
            // handle full fleet order
            ids[i] = handleFullFleetOrder(erc20Contract, receiver);
        }
        emit FleetOrdered(ids, receiver, amount);

        uint256 shares = amount * MAX_FLEET_FRACTION;
        poolShares[receiver] += shares;
        
    }


    /// @notice Order a fleet onchain.
    /// @param fractions The number of fractions to order.
    /// @param erc20Contract The address of the ERC20 contract.
    function orderFleetFraction(uint256 fractions, address erc20Contract, address receiver) external nonReentrant whenNotPaused {
        // value validation
        if (fleetFractionPrice == 0) revert InvalidAmount();
        if (fleetProtocolExpectedValue == 0) revert InvalidAmount();
        if (fleetLiquidityProviderExpectedValue == 0) revert InvalidAmount();
        if (fleetLockPeriod == 0) revert InvalidAmount();
        
        // Input validation
        if (!isTokenValid(erc20Contract)) revert TokenNotAccepted();
        if (erc20Contract == address(0)) revert InvalidAddress();
        if (fractions < MIN_FLEET_FRACTION) revert InvalidFractionAmount();
        if (fractions >= MAX_FLEET_FRACTION) revert FractionExceedsMax();

        if (!isCompliant[receiver]) revert NotCompliant();

        // if first mint ie no last fleetFraction ID we create one
        if (lastFleetFractionID < 1) {
            handleInitialFractionsFleetOrder(fractions, erc20Contract, receiver);
            emit FleetFractionOrdered(lastFleetFractionID, receiver, fractions);

            // add to pool shares
            poolShares[receiver] += fractions;
        }
        // if not first mint
        else {
            // check fraction left of last token id
            uint256 fractionsLeft = MAX_FLEET_FRACTION - totalFractions[lastFleetFractionID];

            // if fractions Left is zero ie last fraction quota completely filled
            if (fractionsLeft < 1) {
                if (fleetOwned[receiver].length + 1 > MAX_FLEET_ORDER_PER_ADDRESS) revert MaxFleetOrderPerAddressExceeded();
                if (totalFleetOrderPerContainer + 1 > maxFleetOrderPerContainer) revert MaxFleetOrderPerContainerExceeded();
                handleInitialFractionsFleetOrder(fractions, erc20Contract, receiver);
                emit FleetFractionOrdered(lastFleetFractionID, receiver, fractions);

                // add to pool shares
                poolShares[receiver] += fractions;
            } else {
                // if requested fractions fit in remaining space
                if (fractions <= fractionsLeft) {
                    handleAdditionalFractionsFleetOrder(fractions, erc20Contract, receiver);
                    emit FleetFractionOrdered(lastFleetFractionID, receiver, fractions);

                    // add to pool shares
                    poolShares[receiver] += fractions;
                }
                // if requested fractions exceed remaining space, split into two orders
                else {
                    if (fleetOwned[receiver].length + 1 > MAX_FLEET_ORDER_PER_ADDRESS) revert MaxFleetOrderPerAddressExceeded();
                        if (totalFleetOrderPerContainer + 1 > maxFleetOrderPerContainer) revert MaxFleetOrderPerContainerExceeded();
                    (uint256[] memory ids, uint256[] memory fractionals) = handleFractionsFleetOrderOverflow(fractions, erc20Contract, fractionsLeft, receiver);
                    emit FleetFractionOverflowOrdered(ids, receiver, fractionals);

                    // add to pool shares
                    poolShares[receiver] += fractions;
                }
            }
        }
    }


    /// @notice Round up a token value (18 decimals) to the next 0.01 unit
    /// @dev Example: 0.7614 → 0.77, 38.071 → 38.08
    /// @param value The amount with 18 decimals
    /// @return Rounded up amount (still 18 decimals)
    function roundUpToTwoDecimals(uint256 value) internal pure returns (uint256) {
        // One "cent" = 0.01 tokens = 1e16 in 18-decimal math
        uint256 cent = 1e16;
        if (value == 0) return 0;
        return ((value + cent - 1) / cent) * cent;
    }


    /// @notice Get the off ramp service fee in USD.
    /// @param fractions The number of fractions to order.
    /// @return The off ramp service fee in USD.
    function getOffRampServiceFeeUSD( uint256 fractions) external view returns (uint256) {
        if (fractions < MIN_FLEET_FRACTION) revert InvalidFractionAmount();
        if (fractions > MAX_FLEET_FRACTION) revert FractionExceedsMax();
        uint256 percentage = 10000 - offRampServiceFee;
        uint256 price = fleetFractionPrice * fractions;
        uint256 fee = price * 10000 / percentage;
        return roundUpToTwoDecimals(fee - price);
    }



    /// @notice Get the initial value of a fleet order.
    /// @param id The id of the fleet order.
    /// @return The initial value of the fleet order.
    function getFleetInitialValuePerOrder(uint256 id) external view returns (uint256) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return fleetInitialValuePerOrder[id];
    }


    /// @notice Get the expected rate of a fleet order.
    /// @param id The id of the fleet order.
    /// @return The protocol expected rate of the fleet order.
    function getFleetProtocolExpectedValuePerOrder(uint256 id) external view returns (uint256) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return fleetProtocolExpectedValuePerOrder[id];
    }


    /// @notice Get the expected rate of a fleet order.
    /// @param id The id of the fleet order.
    /// @return The liquidity provider expected rate of the fleet order.
    function getFleetLiquidityProviderExpectedValuePerOrder(uint256 id) external view returns (uint256) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return fleetLiquidityProviderExpectedValuePerOrder[id];
    }


    /// @notice Get the lock period of a fleet order.
    /// @param id The id of the fleet order.
    /// @return The lock period of the fleet order.
    function getFleetLockPeriodPerOrder(uint256 id) external view returns (uint256) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return fleetLockPeriodPerOrder[id];
    }

    /// @notice Get the vehicle identification number of a fleet order.
    /// @param id The id of the fleet order.
    /// @return The vehicle identification number of the fleet order.
    function getFleetVehicleIdentificationNumberPerOrder(uint256 id) external view returns (string memory) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return fleetVehicleIdentificationNumberPerOrder[id];
    }


    /// @notice Get the license plate number of a fleet order.
    /// @param id The id of the fleet order.
    /// @return The license plate number of the fleet order.
    function getFleetLicensePlateNumberPerOrder(uint256 id) external view returns (string memory) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return fleetLicensePlateNumberPerOrder[id];
    }


    /// @notice Get the fleet orders operated by an address.
    /// @param operator The address of the operator.
    /// @return The fleet orders operated by the address.
    function getFleetOperated(address operator) external view returns (uint256[] memory) {
        return fleetOperated[operator];
    }


    /// @notice Get the fleet orders operated by an address.
    /// @param id The id of the fleet order.
    /// @return The operator of the fleet order.
    function getFleetOperators(uint256 id) external view returns (address[] memory) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return fleetOperators[id];
    }

    /// @notice Get the fleet orders owned by an address.
    /// @param owner The address of the owner.
    /// @return The fleet orders owned by the address.
    function getFleetOwned(address owner) external view returns (uint256[] memory) {
        return fleetOwned[owner];
    }


    /// @notice Get the fleet orders owned by an address.
    /// @param id The id of the fleet order.
    /// @return The addresses sharing the fleet id.
    function getFleetOwners(uint256 id) external view returns (address[] memory) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return fleetOwners[id];
    }


    /// @notice Get the fleet order status of a fleet order.
    /// @param id The id of the fleet order.
    /// @return The fleet order status of the fleet order.
    function getFleetOrderStatus(uint256 id) external view returns (uint256) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return fleetOrderStatus[id];
    }


    function getFleetFractioned(uint256 id) external view returns (bool) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return fleetFractioned[id];
    }


    /// @notice Get the total fleet per container of a fleet order.
    /// @param id The id of the fleet order.
    /// @return The total fleet per container of the fleet order.
    function getTotalFleetPerContainer(uint256 id) external view returns (uint256) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return totalFleetPerContainer[id];
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
    function isValidTransition(uint256 currentStatus, uint256 newStatus, uint256 id) internal view returns (bool) {
        if (currentStatus == INIT) return false;
        if (currentStatus == SHIPPED) return newStatus == ARRIVED;
        if (currentStatus == ARRIVED) return newStatus == CLEARED;
        if (currentStatus == CLEARED) return false;
        if (currentStatus == REGISTERED) return false;
        if (currentStatus == ASSIGNED && fleetOrderYieldContract.getFleetPaymentsDistributed(id) >= fleetLockPeriodPerOrder[id]) return newStatus == TRANSFERRED;
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
            if (currentStatus != 0 && !isValidTransition(currentStatus, status, id)) {
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


    /// @notice Generate the fleet order IDs for a container
    /// @param container The container to generate the fleet order IDs for
    /// @return The fleet order IDs for the container
    function generateContainerFleetOrderIDs(uint256 container) internal view returns (uint256[] memory) {
        uint256 fleetPerContainer = totalFleetPerContainer[container];
        uint256 fleerPerLastContainer = totalFleetPerContainer[container - 1];
        uint256 length = fleetPerContainer - fleerPerLastContainer;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            ids[i] = fleerPerLastContainer + i;
        }
        return ids;
    }


    /// @notice Set the status of multiple fleet orders
    /// @param container The container to set the status for
    /// @param status The new status to set
    function setBulkFleetOrderStatus(uint256 container, uint256 status) external onlyRole(SUPER_ADMIN_ROLE) {

        uint256[] memory ids = generateContainerFleetOrderIDs(container);
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


    /// @notice Start the next container.
    function startNextContainer() internal onlyRole(SUPER_ADMIN_ROLE) {
        totalFleetContainerOrder++;
        totalFleetPerContainer[totalFleetContainerOrder] = maxFleetOrderPerContainer;
        totalFleetOrderPerContainer = 0;
        _pause();
    }


    /// @notice Ship bulk fleet orders in a container with tracking.
    /// @param vins The VINs to create the fleet orders for.
    /// @param tracking The tracking to ship the fleet orders for.
    function shipContainerWithTracking(string[] memory vins, string memory tracking) external onlyRole(SUPER_ADMIN_ROLE) {
        if (totalFleetOrderPerContainer < maxFleetOrderPerContainer) revert MaxFleetOrderPerContainerNotReached();
        if (totalFractions[lastFleetFractionID] < MAX_FLEET_FRACTION) revert MaxFleetOrderPerContainerNotReached();
        startNextContainer();

        uint256[] memory ids = generateContainerFleetOrderIDs(totalFleetContainerOrder);
        if (vins.length != ids.length) revert InvalidAmount();
        for (uint256 i = 0; i < ids.length; i++) {
            setFleetVehicleIdentificationNumberPerOrder(vins[i], ids[i]);
            setFleetOrderStatus(ids[i], SHIPPED);
        }
        setTrackingPerContainer(tracking, totalFleetContainerOrder);
    }


    /// @notice Register a fleet order with a license plate number.
    /// @param id The id of the fleet order to register.
    /// @param licensePlateNumber The license plate number to register the fleet order with.
    function registerFleetOrderLicensePlateNumber(uint256 id, string memory licensePlateNumber) external onlyRole(SUPER_ADMIN_ROLE) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        if (fleetOrderStatus[id] != CLEARED) revert InvalidStatus();
        setFleetLicensePlateNumberPerOrder(licensePlateNumber, id);
    }


    /// @notice Assign a fleet operator to a fleet order.
    /// @param id The id of the fleet order.
    /// @param operator The address of the operator.
    function assignFleetOperator(uint256 id, address operator) external onlyRole(SUPER_ADMIN_ROLE) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        if (operator == address(0)) revert InvalidAddress();
        if (fleetOrderStatus[id] != REGISTERED) revert InvalidStatus();
        if (isAddressFleetOperator(operator, id)) revert OperatorAlreadyAssigned();
        addFleetOperator(operator, id);
        addFleetOperated(operator, id);
        setFleetOrderStatus(id, ASSIGNED);
    }


    /// @notice Get the current status of a fleet order
    /// @param id The id of the fleet order to get the status for
    /// @return string The human-readable status string
    function getFleetOrderStatusReadable(uint256 id) public view returns (string memory) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        uint256 status = fleetOrderStatus[id];
        
        if (status == INIT) return "Initialized";
        if (status == SHIPPED) return "Shipped";
        if (status == ARRIVED) return "Arrived";
        if (status == CLEARED) return "Cleared";
        if (status == REGISTERED) return "Registered";
        if (status == ASSIGNED) return "Assigned";
        if (status == TRANSFERRED) return "Transferred";
        
        revert InvalidStatus();
    }


    /// @notice Get the total supply of a fleet order.
    /// @param id The id of the fleet order.
    /// @return The total supply of the fleet order.
    function totalSupply(uint256 id) external view returns (uint256) {
        if (id == 0) revert InvalidId();
        if (id > totalFleet) revert IdDoesNotExist();
        return totalFractions[id];
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
    ) public override nonReentrant returns (bool) {
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
    ) public override nonReentrant returns (bool) {
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
    function withdrawFleetOrderSales(address token, address to) external onlyRole(WITHDRAWAL_ROLE) nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        IERC20 tokenContract = IERC20(token);
        uint256 amount = tokenContract.balanceOf(address(this));
        if (amount == 0) revert NotEnoughTokens();
        tokenContract.safeTransfer(to, amount);
        emit FleetSalesWithdrawn(token, to, amount);
    }


    receive() external payable { revert NoNativeTokenAccepted(); }
    fallback() external payable { revert NoNativeTokenAccepted(); }

    // =================================================== ADMIN MANAGEMENT ====================================================

    /// @notice Grant compliance role to an address
    /// @param account The address to grant the compliance role to
    function grantComplianceRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(COMPLIANCE_ROLE, account);
    }

    /// @notice Revoke compliance role from an address
    /// @param account The address to revoke the compliance role from
    function revokeComplianceRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(COMPLIANCE_ROLE, account);
    }

    /// @notice Grant withdrawal role to an address
    /// @param account The address to grant the withdrawal role to
    function grantWithdrawalRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(WITHDRAWAL_ROLE, account);
    }

    /// @notice Revoke withdrawal role from an address
    /// @param account The address to revoke the withdrawal role from
    function revokeWithdrawalRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(WITHDRAWAL_ROLE, account);
    }

    /// @notice Grant super admin role to an address
    /// @param account The address to grant the super admin role to
    function grantSuperAdminRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SUPER_ADMIN_ROLE, account);
    }

    /// @notice Revoke super admin role from an address
    /// @param account The address to revoke the super admin role from
    function revokeSuperAdminRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(SUPER_ADMIN_ROLE, account);
    }

    /// @notice Check if an address has compliance role
    /// @param account The address to check
    /// @return bool True if the address has compliance role
    function isCompliance(address account) external view returns (bool) {
        return hasRole(COMPLIANCE_ROLE, account);
    }

    /// @notice Check if an address has withdrawal role
    /// @param account The address to check
    /// @return bool True if the address has withdrawal role
    function isWithdrawal(address account) external view returns (bool) {
        return hasRole(WITHDRAWAL_ROLE, account);
    }

    /// @notice Check if an address has super admin role
    /// @param account The address to check
    /// @return bool True if the address has super admin role
    function isSuperAdmin(address account) external view returns (bool) {
        return hasRole(SUPER_ADMIN_ROLE, account);
    }

}

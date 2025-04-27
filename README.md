# 3WB Fleet Order Book Contract

A Solidity smart contract implementing fractional and full pre-orders for three-wheeler fleets on Celo, using ERC-6909 for on-chain tokenized order tracking.

## 📖 Overview

The **FleetOrderBook** contract lets investors place:
- **Fractional orders**: buy a share of a 3-wheeler fleet.
- **Full orders**: purchase an entire 3-wheeler.

Each order mints an ERC-6909 “order token” that represents the buyer’s stake. The contract supports pause/unpause, modular event logging, and reentrancy protection.

## 🚀 Features

- **ERC-6909 Compliant**  
  Tracks total and per-ID supply, plus content URIs.

- **Fractional & Full Orders**  
  - `orderFractions(uint256 fleetId, uint256 fractions)`  
  - `orderFull(uint256 fleetId)`

- **Pause/Unpause**  
  Only owner can pause or resume state-changing functions.

- **ReentrancyGuard**  
  Protects against reentrant calls.

- **Ownable**  
  Owner-only configuration and withdrawal.

- **Event Logging**  
  `OrderPlaced`, `OrderFulfilled`, `Paused`, `Unpaused`, etc.

## 📋 Contract Details

- **Solidity Version**: `^0.8.13`  
- **Imports**:  
  - `solmate/tokens/ERC6909.sol`  
  - `@openzeppelin/contracts/access/Ownable.sol`  
  - `@openzeppelin/contracts/utils/Pausable.sol`  
  - `@openzeppelin/contracts/utils/ReentrancyGuard.sol`

### Key State Variables

```solidity
mapping(uint256 => uint256) public totalFractionsPerFleet;
uint256 public nextFleetOrderId;
```

### Core Functions

```solidity
function orderFractions(uint256 fleetId, uint256 fractions) external payable;
function orderFull(uint256 fleetId) external payable;
function pause() external onlyOwner;
function unpause() external onlyOwner;
function withdraw(address to) external onlyOwner;
```

### Events

```solidity
event OrderPlaced(
  uint256 indexed orderId,
  address indexed buyer,
  uint256 fleetId,
  uint256 amount,
  bool isFull
);

event OrderFulfilled(uint256 indexed orderId);
event Paused(address account);
event Unpaused(address account);
```

## 🛠️ Tech Stack

- **Compiler**: Solidity `0.8.13`  
- **Framework**: Foundry (Forge) for build, test, and deployment  
- **Testing**: Foundry tests in `test/`  
- **Contracts**: `src/FleetOrderBook.sol` plus interfaces

## 📦 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) installed (`forge`, `cast`, `anvil`)  
- Node.js (for scripts)  
- A Celo RPC endpoint and private key for deployment  

### Installation & Compilation

```bash
git clone https://github.com/3-Wheeler-Bike-Club/3-wheeler-bike-club-fleet-order-book-contract.git
cd 3-wheeler-bike-club-fleet-order-book-contract

# Ensure Foundry is installed/updated
foundryup

# Compile contracts
forge build
```

### Running Tests

```bash
forge test
```

### Deployment

1. Create a `.env` file in project root:

   ```env
   PRIVATE_KEY=your_deployer_private_key
   CELO_RPC_URL=https://forno.celo.org
   ```

2. Run the deployment script:

   ```bash
   forge script script/Deploy.s.sol \
     --rpc-url $CELO_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast
   ```

3. Note the deployed contract address printed in console.

## 📁 Directory Structure

```
/
├── src/                   # Solidity source files
│   └── FleetOrderBook.sol
├── test/                  # Foundry tests
│   └── FleetOrderBook.t.sol
├── script/                # Deployment scripts
│   └── Deploy.s.sol
├── lib/                   # External dependencies (ERC6909, etc.)
├── foundry.toml           # Foundry configuration
└── README.md              # This README
```

## 🤝 Contributing

1. Fork the repository  
2. Create your branch:  
   ```bash
   git checkout -b feature/my-feature
   ```
3. Commit your changes:  
   ```bash
   git commit -m "Add my feature"
   ```
4. Push to your branch:  
   ```bash
   git push origin feature/my-feature
   ```
5. Open a Pull Request

Please ensure your code adheres to existing style, and add tests for new features.

## 📄 License

This project is licensed under the MIT License.
```


# 3WB Fleet Order Book Contract

A Solidity smart contract for managing fractional and full investment pre-orders of three-wheeler fleets on Celo by minting ERC-6909 tokens as digital receipts.

## 🚀 High-Level Features

- **Fractional Orders**: Investors purchase between 1 and 50 fractions of a specific fleet (max fraction constant = 50).
- **Full Orders**: Investors acquire all available fractions (50) in one transaction.
- **ERC-6909 Tokenization**: Mints ERC-6909 tokens keyed by fleet ID, tracking balances and supply.
- **Pausable**: Owner can pause/unpause all order-related functions.
- **ReentrancyGuard**: Protects against reentrant attacks on state-changing methods.
- **Configurable Parameters**: Owner can set fraction price (in USD), max total orders, and contract URI.
- **ERC20 Payments**: Supports multiple stablecoin ERC20 tokens for order fees.
- **Fleet Status Tracking**: Bitmask-based lifecycle states (Initialized → Created → Shipped → Arrived → Cleared → Registered → Assigned → Transferred).
- **Ownership Transfer Overrides**: Custom `transfer` and `transferFrom` to maintain internal order ownership mappings.
- **Bulk Status Updates**: Owner can update statuses for up to 50 orders in one call.

## 📢 Public API

| Function                                                                                 | Description                                                                         |
| ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `orderFleet(uint256 fractions, address erc20Token)`                                      | Place a fractional or full order paying with `erc20Token`. Fractions 1–50 allowed.  |
| `orderMultipleFleet(uint256 amount, address erc20Token)`                                 | Place `amount` full orders (each = 50 fractions).                                    |
| `getFleetOwned(address owner) view returns (uint256[])`                                  | Retrieve all fleet order IDs owned by `owner`.                                       |
| `setFleetFractionPrice(uint256 price)`                                                   | Owner: set price per fraction (non-zero).                                          |
| `setMaxFleetOrder(uint256 maxOrders)`                                                    | Owner: increase max total orders allowed.                                           |
| `addERC20(address erc20Token)`                                                           | Owner: add an accepted ERC20 token for payments.                                    |
| `removeERC20(address erc20Token)`                                                        | Owner: remove an accepted ERC20 token.                                              |
| `setContractURI(string memory uri)`                                                      | Owner: set base URI for `tokenURI`.                                                 |
| `withdrawFleetOrderSales(address token, address to)`                                     | Owner: withdraw all collected `token` funds to `to`.                                 |
| `pause()` / `unpause()`                                                                   | Owner: pause or resume order functions.                                             |
| `setBulkFleetOrderStatus(uint256[] memory ids, uint256 status)`                          | Owner: update lifecycle status for multiple orders.                                 |
| `getFleetOrderStatus(uint256 id) view returns (string)`                                  | View human-readable status of order `id`.                                           |
| `tokenURI(uint256 id) public view returns (string)`                                      | Returns `contractURI + id`.                                                         |
| `transfer(address to, uint256 id, uint256 amount)` override                              | ERC-6909: transfer `amount` tokens of `id` to `to`, maintaining internal mappings.    |
| `transferFrom(address from, address to, uint256 id, uint256 amount)` override            | ERC-6909: transfer on behalf of `from` respecting approvals.                         |

## 📋 Events

- `event FleetOrdered(uint256 indexed fleetId, address indexed buyer)`
- `event FleetFractionOrdered(uint256 indexed fleetId, address indexed buyer, uint256 indexed fractions)`
- `event FleetSalesWithdrawn(address indexed token, address indexed to, uint256 amount)`
- `event ERC20Added(address indexed token)`
- `event ERC20Removed(address indexed token)`
- `event FleetFractionPriceChanged(uint256 oldPrice, uint256 newPrice)`
- `event MaxFleetOrderChanged(uint256 oldMax, uint256 newMax)`
- `event FleetOrderStatusChanged(uint256 indexed id, uint256 status)`

## 🛠️ Setup & Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (`forge`, `anvil`) installed
- Node.js (for any deployment/testing scripts)
- A Celo RPC endpoint and a deployer private key

### Installation & Compilation

```bash
git clone https://github.com/3-Wheeler-Bike-Club/3-wheeler-bike-club-fleet-order-book-contract.git
cd 3-wheeler-bike-club-fleet-order-book-contract

foundryup            # Ensure Foundry is up to date
forge build          # Compile contracts
```

### Testing

```bash
forge test
```

### Deployment

1. Create a `.env` file at project root:

   ```env
   PRIVATE_KEY=your_deployer_private_key
   CELO_RPC_URL=https://forno.celo.org
   ```

2. Run the deploy script:

   ```bash
   forge script scripts/Deploy.s.sol \
     --rpc-url $CELO_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast
   ```

3. Note the deployed contract address from the console.

## 📁 Directory Structure

```
├── src/                   # Solidity source files
│   └── FleetOrderBook.sol
├── src/interfaces/       # ERC-6909 and content URI interfaces
├── scripts/               # Deployment scripts
├── foundry.toml           # Foundry config
└── README.md              # This file
```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/...`)
3. Write code and accompanying tests
4. Commit, push, and open a PR

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
```


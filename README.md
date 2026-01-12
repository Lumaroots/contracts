# LumaRoots Smart Contracts

A gamified reforestation protocol on Mantle Network that bridges virtual engagement with real-world tree planting through Tree-Nation partnership.

## Overview

LumaRoots is a Real World Asset (RWA) protocol that tokenizes tree ownership through NFT certificates linked to actual trees. Users engage through a daily watering game, earning points and growing their virtual forest while contributing to real reforestation efforts.

### Features

- **Free Starter Tree** - Zero-friction onboarding for new users
- **Daily Watering Game** - Earn points every 24 hours with streak bonuses
- **Virtual Forest** - Redeem points for virtual trees (500 points = 1 tree)
- **Premium Trees** - Purchase enhanced virtual trees with MNT
- **Real Tree Donation** - Plant real trees through Tree-Nation integration
- **NFT Certificates** - ERC-721 proof of real tree ownership

## Architecture

The protocol uses UUPS proxy pattern for upgradeability:

```
LumaRootsUpgradeable
├── ERC721URIStorage (NFT Certificates)
├── OwnableUpgradeable (Admin controls)
├── PausableUpgradeable (Emergency stop)
└── ReentrancyGuardUpgradeable (Payment security)
```

## Contracts

| Contract | Description |
|----------|-------------|
| `LumaRootsUpgradeable.sol` | Main protocol contract with all core features |
| `MockPriceFeed.sol` | Chainlink-compatible price oracle for testnet |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

## Installation

```bash
git clone https://github.com/dwlpra/lumaroots-contract.git
cd lumaroots-contract
forge install
forge build
```

## Configuration

Copy the environment template and configure your values:

```bash
cp .env.example .env
```

Required environment variables:

```
PRIVATE_KEY=your_deployer_private_key
MANTLE_SEPOLIA_RPC=https://rpc.sepolia.mantle.xyz
```

## Deployment

### Deploy to Mantle Sepolia Testnet

```bash
source .env

forge script script/DeployUpgradeable.s.sol:DeployUpgradeable \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --broadcast \
  --verify \
  -vvvv
```

### Verify Contracts (if not auto-verified)

```bash
forge verify-contract <IMPLEMENTATION_ADDRESS> src/LumaRootsUpgradeable.sol:LumaRootsUpgradeable \
  --chain-id 5003 \
  --verifier blockscout \
  --verifier-url https://explorer.sepolia.mantle.xyz/api
```

## Deployed Contracts (Mantle Sepolia)

| Contract | Address |
|----------|---------|
| Proxy | `0x738AEce732a90688a85B45FB700f8197E75a4995` |
| Implementation | `0x716672e30DAD2484a25Cb7Cba9B5C3f50fe4A312` |
| MockPriceFeed | `0xF3581457CeC63912E510E9601e59b9224f2277d4` |

Note: Interact with the Proxy address for all function calls.

## Usage

### User Functions

```solidity
// Claim free starter tree (one per wallet)
function claimFreeTree() external

// Water plants daily to earn points
function waterPlant() external

// Redeem points for virtual trees
function redeemPointsForTree(uint256 numberOfTrees) external

// Purchase premium virtual trees
function purchasePremiumVirtualTree(uint256 quantity) external payable

// Donate to plant real trees via Tree-Nation
function purchaseTree(uint256 speciesId, uint256 projectId, uint256 quantity) external payable
```

### View Functions

```solidity
// Get user forest summary
function getUserForest(address user) external view returns (
    uint256 virtualTrees,
    uint256 realTrees,
    uint256 totalTrees,
    uint256 points,
    bool hasFreeTree
)

// Check if user can water now
function canWaterNow(address user) external view returns (bool canWater, uint256 timeRemaining)

// Calculate points user would earn from watering
function calculateWaterPoints(address user) external view returns (
    uint256 basePoints,
    uint256 streakBonus,
    uint256 totalPoints
)
```

## Default Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| pointsPerWater | 10 | Base points earned per water |
| streakBonusPoints | 5 | Additional points per streak day |
| maxStreakBonus | 7 | Maximum streak multiplier |
| pointsPerVirtualTree | 500 | Points required to redeem a tree |
| cooldownTime | 24 hours | Time between watering |
| minPurchaseAmount | 0.001 MNT | Minimum real tree donation |
| premiumTreePrice | 0.001 MNT | Price per premium virtual tree |

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/LumaRoots.t.sol

# Gas report
forge test --gas-report
```

## Security Considerations

- UUPS proxy with owner-only upgrade authorization
- ReentrancyGuard on all payment functions
- Pausable for emergency situations
- Input validation on all external functions

## Project Structure

```
├── src/
│   ├── LumaRootsUpgradeable.sol    # Main contract
│   ├── MockPriceFeed.sol           # Price oracle mock
│   └── interfaces/
│       └── IPriceFeed.sol          # Oracle interface
├── script/
│   └── DeployUpgradeable.s.sol     # Deployment script
├── test/
│   ├── LumaRoots.t.sol             # Main contract tests
│   └── MockPriceFeed.t.sol         # Oracle tests
└── lib/                            # Dependencies
```

## License

MIT

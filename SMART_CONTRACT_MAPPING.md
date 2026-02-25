# 🌳 LumaRoots Smart Contract - Functional Mapping

## 📋 Overview

**Contract Name:** `LumaRootsUpgradeable`  
**Version:** 1.0.0  
**License:** MIT  
**Solidity:** ^0.8.24  
**Network:** Mantle (MNT)

> **Tagline:** *"Gamified reforestation protocol - Play to Plant, Own Real Impact"*

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    LumaRootsUpgradeable                         │
├─────────────────────────────────────────────────────────────────┤
│  Inherits:                                                      │
│  ├── Initializable (Upgradeable pattern)                        │
│  ├── ERC721URIStorageUpgradeable (NFT Certificate)              │
│  ├── OwnableUpgradeable (Admin control)                         │
│  ├── PausableUpgradeable (Emergency pause)                      │
│  ├── ReentrancyGuard (Security)                                 │
│  └── UUPSUpgradeable (Proxy upgrade pattern)                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📊 Data Structures

### 1. UserPlant (Gamification Data)
```solidity
struct UserPlant {
    uint256 lastWaterTime;    // Timestamp terakhir menyiram
    uint256 waterStreak;      // Streak harian berturut-turut
    uint256 totalWaterCount;  // Total berapa kali menyiram
}
```

### 2. Purchase (Real Tree Purchase Record)
```solidity
struct Purchase {
    address buyer;        // Alamat pembeli
    uint256 speciesId;    // ID spesies pohon
    uint256 projectId;    // ID proyek Tree-Nation
    uint256 amountPaid;   // Jumlah MNT yang dibayar
    uint256 timestamp;    // Waktu pembelian
    bool processed;       // Sudah diproses backend?
    bool nftMinted;       // NFT sudah di-mint?
}
```

---

## 🗂️ State Variables

### Core Settings
| Variable | Type | Default | Deskripsi |
|----------|------|---------|-----------|
| `cooldownTime` | uint256 | 24 hours | Waktu tunggu antar siram |
| `minPurchaseAmount` | uint256 | 0.001 ether | Minimum pembelian pohon |
| `premiumTreePrice` | uint256 | 0.001 ether | Harga premium virtual tree |

### Points System Settings
| Variable | Type | Default | Deskripsi |
|----------|------|---------|-----------|
| `pointsPerWater` | uint256 | 10 | Poin dasar per siram |
| `streakBonusPoints` | uint256 | 5 | Bonus per hari streak |
| `maxStreakBonus` | uint256 | 7 | Maksimal streak bonus (7 hari) |
| `pointsPerVirtualTree` | uint256 | 500 | Poin untuk redeem 1 virtual tree |

### User Mappings
| Mapping | Deskripsi |
|---------|-----------|
| `userPlants[address]` | Data gamifikasi user |
| `virtualTreeCount[address]` | Jumlah virtual trees user |
| `premiumTreeCount[address]` | Jumlah premium trees user |
| `hasClaimedFreeTree[address]` | Status klaim free tree |
| `userPoints[address]` | Poin yang dimiliki user |
| `userPurchaseIds[address]` | Array purchase IDs user |

### NFT & Purchase Mappings
| Mapping | Deskripsi |
|---------|-----------|
| `purchases[uint256]` | Data purchase by ID |
| `tokenIdToPurchaseId[uint256]` | Link NFT ke purchase |

---

## 🎮 Fungsi Utama (User Functions)

### 1. 🆓 Claim Free Tree
```solidity
function claimFreeTree() external whenNotPaused
```
| Aspek | Detail |
|-------|--------|
| **Tujuan** | Klaim 1 pohon virtual gratis sebagai starter |
| **Syarat** | Belum pernah klaim sebelumnya |
| **Effect** | `hasClaimedFreeTree = true`, `virtualTreeCount += 1` |
| **Event** | `FreeTreeClaimed(user, timestamp)` |

---

### 2. 💧 Water Plant (Gamifikasi Harian)
```solidity
function waterPlant() external whenNotPaused
```
| Aspek | Detail |
|-------|--------|
| **Tujuan** | Siram tanaman harian, earn points |
| **Syarat** | Punya minimal 1 pohon, cooldown selesai |
| **Points Formula** | `(basePoints × totalTrees) + streakBonus` |
| **Streak Reset** | Jika miss > 2× cooldown |
| **Event** | `PlantWatered(user, streak, totalWater, points, totalPoints, timestamp)` |

**Rumus Poin:**
```
Base Points = pointsPerWater × totalTrees
Streak Bonus = min(streakDays - 1, maxStreakBonus) × streakBonusPoints

Contoh: User punya 5 pohon, streak hari ke-4
Base = 10 × 5 = 50 poin
Bonus = 3 × 5 = 15 poin
Total = 65 poin per hari
```

---

### 3. 🎁 Redeem Points for Virtual Tree
```solidity
function redeemPointsForTree(uint256 numberOfTrees) external whenNotPaused
```
| Aspek | Detail |
|-------|--------|
| **Tujuan** | Tukar poin menjadi virtual trees |
| **Cost** | 500 poin per 1 virtual tree |
| **Effect** | `userPoints -= cost`, `virtualTreeCount += numberOfTrees` |
| **Event** | `VirtualTreeRedeemed(user, pointsSpent, newTreeCount, timestamp)` |

---

### 4. 💎 Purchase Premium Virtual Tree
```solidity
function purchasePremiumVirtualTree(uint256 quantity) external payable nonReentrant whenNotPaused
```
| Aspek | Detail |
|-------|--------|
| **Tujuan** | Beli virtual trees dengan MNT |
| **Price** | 0.001 MNT per tree |
| **Max per TX** | 10 trees |
| **Refund** | Otomatis jika bayar lebih |
| **Event** | `PremiumVirtualTreePurchased(user, qty, amount, newTotal, timestamp)` |

---

### 5. 🌲 Purchase Real Tree (RWA)
```solidity
function purchaseTree(uint256 speciesId, uint256 projectId, uint256 quantity) 
    external payable nonReentrant whenNotPaused
```
| Aspek | Detail |
|-------|--------|
| **Tujuan** | Beli pohon nyata via Tree-Nation |
| **Min Amount** | 0.001 MNT per pohon |
| **Max Quantity** | 100 per transaksi |
| **Flow** | Bayar → Purchase record → Backend process → Tree-Nation API |
| **Event** | `TreePurchased(purchaseId, buyer, speciesId, projectId, amount, timestamp)` |

---

## 👑 Admin Functions (onlyOwner)

### Purchase & NFT Management
| Fungsi | Deskripsi |
|--------|-----------|
| `markPurchaseProcessed(purchaseId)` | Tandai purchase sudah diproses backend |
| `mintCertificate(purchaseId, tokenURI, treeNationId)` | Mint NFT sertifikat setelah konfirmasi Tree-Nation |

### Settings Management
| Fungsi | Parameters | Deskripsi |
|--------|------------|-----------|
| `setCooldownTime(seconds)` | uint256 | Atur waktu cooldown |
| `setMinPurchaseAmount(amount)` | uint256 | Atur minimum purchase |
| `setPremiumTreePrice(newPrice)` | uint256 | Atur harga premium tree |
| `setPointsSettings(...)` | 4 params | Atur semua parameter poin |
| `awardPoints(user, amount)` | address, uint256 | Beri poin ke user (reward) |

### Contract Control
| Fungsi | Deskripsi |
|--------|-----------|
| `pause()` | Pause semua aktivitas contract |
| `unpause()` | Resume aktivitas contract |
| `emergencyWithdraw()` | Tarik semua balance ke owner |

---

## 📖 View Functions (Read Only)

### User Data
| Fungsi | Return | Deskripsi |
|--------|--------|-----------|
| `getTotalTreeCount(user)` | uint256 | Total virtual + real trees |
| `getUserForest(user)` | tuple | virtualTrees, realTrees, total, points, hasFreeTree |
| `getUserPlant(user)` | tuple | lastWaterTime, streak, totalWaterCount |
| `getUserPurchases(user)` | uint256[] | Array of purchase IDs |
| `getUserPurchaseCount(user)` | uint256 | Jumlah purchase |
| `getUserPremiumTrees(user)` | uint256 | Jumlah premium trees |

### Watering Helpers
| Fungsi | Return | Deskripsi |
|--------|--------|-----------|
| `canWaterNow(user)` | (bool, uint256) | Bisa siram? + sisa waktu |
| `calculateWaterPoints(user)` | (base, bonus, total) | Preview poin yang akan didapat |

### Contract Stats
| Fungsi | Return | Deskripsi |
|--------|--------|-----------|
| `totalSupply()` | uint256 | Total NFT yang sudah di-mint |
| `totalPurchases()` | uint256 | Total purchase records |
| `getPremiumTreeStats()` | (total, price) | Stats premium trees |
| `getPointsSettings()` | tuple | Semua settings poin |
| `getImplementation()` | address | Alamat implementation contract |

---

## 📡 Events

### User Activity Events
```solidity
PlantWatered(user, newStreak, totalWaterCount, pointsEarned, totalPoints, timestamp)
FreeTreeClaimed(user, timestamp)
VirtualTreeRedeemed(user, pointsSpent, newTreeCount, timestamp)
TreePurchased(purchaseId, buyer, speciesId, projectId, amountPaid, timestamp)
PremiumVirtualTreePurchased(user, quantity, amountPaid, newPremiumTotal, timestamp)
```

### NFT Events
```solidity
CertificateMinted(tokenId, owner, purchaseId, treeNationId)
```

### Admin Events
```solidity
CooldownTimeUpdated(oldCooldown, newCooldown)
MinPurchaseAmountUpdated(oldMin, newMin)
PointsSettingsUpdated(pointsPerWater, streakBonus, maxStreak, redeemCost)
PremiumTreePriceUpdated(oldPrice, newPrice)
ContractPaused(by, timestamp)
ContractUnpaused(by, timestamp)
```

---

## 🔄 User Journey Flowchart

```
┌─────────────────┐
│   New User      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ claimFreeTree() │ ──► Gets 1 Virtual Tree (FREE)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  waterPlant()   │ ──► Daily, earn 10+ points
│   (daily)       │     Build streak for bonus
└────────┬────────┘
         │
         ├──────────────────────────────────┐
         ▼                                  ▼
┌─────────────────────────┐    ┌─────────────────────────────┐
│ redeemPointsForTree()   │    │ purchasePremiumVirtualTree()│
│ (500 points = 1 tree)   │    │ (0.001 MNT = 1 tree)        │
└────────┬────────────────┘    └──────────────┬──────────────┘
         │                                     │
         └──────────────┬──────────────────────┘
                        │
                        ▼
               More trees = More points per water!
                        │
                        ▼
┌─────────────────────────────────────────────┐
│           purchaseTree() (RWA)              │
│  Real tree planted via Tree-Nation!         │
│  ──► Backend processes                      │
│  ──► NFT Certificate minted                 │
└─────────────────────────────────────────────┘
```

---

## 🔐 Security Features

| Feature | Implementation |
|---------|----------------|
| **Reentrancy Protection** | `ReentrancyGuard` on payable functions |
| **Pausable** | Emergency pause capability |
| **Access Control** | `onlyOwner` for admin functions |
| **Upgradeable** | UUPS pattern for future updates |
| **Cooldown System** | Prevents spam watering |

---

## 📁 Related Files

| File | Deskripsi |
|------|-----------|
| [LumaRootsUpgradeable.sol](src/LumaRootsUpgradeable.sol) | Main contract |
| [IPriceFeed.sol](src/interfaces/IPriceFeed.sol) | Price oracle interface |
| [MockPriceFeed.sol](src/MockPriceFeed.sol) | Mock oracle untuk testnet |
| [DeployUpgradeable.s.sol](script/DeployUpgradeable.s.sol) | Deployment script |

---

## 💡 Key Formulas

### Points Calculation
```
Daily Points = (pointsPerWater × totalTrees) + streakBonus
where:
  streakBonus = min(streakDays - 1, 7) × streakBonusPoints
```

### Virtual Tree Redemption
```
Required Points = numberOfTrees × pointsPerVirtualTree (500)
```

### Premium Tree Purchase
```
Total Cost = quantity × premiumTreePrice (0.001 MNT)
Max quantity per TX = 10
```

---

*Last Updated: January 2026*

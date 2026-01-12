// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/**
 * @title LumaRootsUpgradeable
 * @author LumaRoots Team
 * @notice Gamified reforestation protocol - Play to Plant, Own Real Impact
 * @dev UUPS upgradeable, ERC721 for tree certificates, integrates with Tree-Nation API
 */
contract LumaRootsUpgradeable is 
    Initializable,
    ERC721URIStorageUpgradeable, 
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable 
{
    
    // ============ Structs ============
    struct UserPlant {
        uint256 lastWaterTime;
        uint256 waterStreak;
        uint256 totalWaterCount;
    }

    struct Purchase {
        address buyer;
        uint256 speciesId;
        uint256 projectId;
        uint256 amountPaid;      // Amount in MNT
        uint256 timestamp;
        bool processed;          // Backend has processed this purchase
        bool nftMinted;          // NFT certificate has been minted
    }

    // ============ State Variables ============
    // @dev Storage layout is upgrade-safe - only append new variables at the end
    
    mapping(address => UserPlant) public userPlants;
    uint256 public cooldownTime;
    
    mapping(uint256 => Purchase) public purchases;
    mapping(address => uint256[]) public userPurchaseIds;
    uint256 private _purchaseIdCounter;
    
    uint256 private _tokenIdCounter;
    mapping(uint256 => uint256) public tokenIdToPurchaseId;
    
    uint256 public minPurchaseAmount;

    // Virtual Trees & Points System
    mapping(address => uint256) public virtualTreeCount;
    mapping(address => bool) public hasClaimedFreeTree;
    mapping(address => uint256) public userPoints;
    uint256 public pointsPerWater;
    uint256 public streakBonusPoints;
    uint256 public maxStreakBonus;
    uint256 public pointsPerVirtualTree;

    string public constant VERSION = "1.0.0";

    // Premium Virtual Trees
    mapping(address => uint256) public premiumTreeCount;
    uint256 public totalPremiumTrees;
    uint256 public premiumTreePrice;
    uint256 public constant MAX_PREMIUM_PER_TX = 10;

    // ============ Events ============
    
    event PlantWatered(
        address indexed user, 
        uint256 newStreak, 
        uint256 totalWaterCount, 
        uint256 pointsEarned,
        uint256 totalPoints,
        uint256 timestamp
    );
    
    event FreeTreeClaimed(address indexed user, uint256 timestamp);
    event VirtualTreeRedeemed(address indexed user, uint256 pointsSpent, uint256 newTreeCount, uint256 timestamp);
    
    event TreePurchased(
        uint256 indexed purchaseId,
        address indexed buyer,
        uint256 speciesId,
        uint256 projectId,
        uint256 amountPaid,
        uint256 timestamp
    );
    
    event CertificateMinted(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 indexed purchaseId,
        string treeNationId
    );
    
    event CooldownTimeUpdated(uint256 oldCooldown, uint256 newCooldown);
    event MinPurchaseAmountUpdated(uint256 oldMin, uint256 newMin);
    event PointsSettingsUpdated(uint256 pointsPerWater, uint256 streakBonus, uint256 maxStreak, uint256 redeemCost);
    event ContractPaused(address indexed by, uint256 timestamp);
    event ContractUnpaused(address indexed by, uint256 timestamp);
    event PremiumVirtualTreePurchased(
        address indexed user,
        uint256 quantity,
        uint256 amountPaid,
        uint256 newPremiumTotal,
        uint256 timestamp
    );

    event PremiumTreePriceUpdated(uint256 oldPrice, uint256 newPrice);

    // ============ Constructor & Initializer ============
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize contract with default settings
    function initialize(address initialOwner) public initializer {
        __ERC721_init("LumaRoots Tree Certificate", "LRTC");
        __ERC721URIStorage_init();
        __Ownable_init(initialOwner);
        __Pausable_init();

        _tokenIdCounter = 0;
        _purchaseIdCounter = 0;
        cooldownTime = 24 hours;
        minPurchaseAmount = 0.001 ether;
        pointsPerWater = 10;
        streakBonusPoints = 5;
        maxStreakBonus = 7;
        pointsPerVirtualTree = 500;
        premiumTreePrice = 0.001 ether;
    }

    // ============ UUPS Upgrade ============
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Core Functions ============

    /// @notice Claim free starter tree (one per wallet, gasless via Privy)
    function claimFreeTree() external whenNotPaused {
        require(!hasClaimedFreeTree[msg.sender], "Already claimed free tree");
        
        hasClaimedFreeTree[msg.sender] = true;
        virtualTreeCount[msg.sender] = 1;
        
        emit FreeTreeClaimed(msg.sender, block.timestamp);
    }

    /// @notice Redeem points for virtual trees
    function redeemPointsForTree(uint256 numberOfTrees) external whenNotPaused {
        require(numberOfTrees > 0, "Must redeem at least 1 tree");
        
        uint256 totalCost = pointsPerVirtualTree * numberOfTrees;
        require(userPoints[msg.sender] >= totalCost, "Not enough points");
        
        userPoints[msg.sender] -= totalCost;
        virtualTreeCount[msg.sender] += numberOfTrees;
        
        emit VirtualTreeRedeemed(msg.sender, totalCost, virtualTreeCount[msg.sender], block.timestamp);
    }

    // ============ Real Tree Purchases (RWA) ============

    /// @notice Purchase real trees - triggers Tree-Nation API via backend
    function purchaseTree(
        uint256 speciesId,
        uint256 projectId,
        uint256 quantity
    ) external payable nonReentrant whenNotPaused {
        require(quantity > 0 && quantity <= 100, "Quantity must be 1-100");
        require(msg.value >= minPurchaseAmount * quantity, "Below minimum purchase amount");
        require(speciesId > 0, "Invalid species ID");
        require(projectId > 0, "Invalid project ID");

        // Calculate amount per tree
        uint256 amountPerTree = msg.value / quantity;

        // Create a purchase record for each tree
        for (uint256 i = 0; i < quantity; i++) {
            uint256 purchaseId = _purchaseIdCounter;
            _purchaseIdCounter += 1;

            purchases[purchaseId] = Purchase({
                buyer: msg.sender,
                speciesId: speciesId,
                projectId: projectId,
                amountPaid: amountPerTree,
                timestamp: block.timestamp,
                processed: false,
                nftMinted: false
            });

            userPurchaseIds[msg.sender].push(purchaseId);

            emit TreePurchased(
                purchaseId,
                msg.sender,
                speciesId,
                projectId,
                amountPerTree,
                block.timestamp
            );
        }

        // Transfer funds to owner (for Tree Nation credit purchase)
        (bool success, ) = payable(owner()).call{value: msg.value}("");
        require(success, "Transfer to owner failed");
    }

    /// @notice Mint NFT certificate after Tree-Nation confirmation (owner only)
    function mintCertificate(
        uint256 purchaseId,
        string memory tokenURI,
        string memory treeNationId
    ) external onlyOwner {
        Purchase storage purchase = purchases[purchaseId];

        require(purchase.buyer != address(0), "Purchase not found");
        require(purchase.processed, "Purchase not yet processed");
        require(!purchase.nftMinted, "NFT already minted");

        uint256 newTokenId = _tokenIdCounter;
        _tokenIdCounter += 1;
        
        _safeMint(purchase.buyer, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        
        tokenIdToPurchaseId[newTokenId] = purchaseId;
        purchase.nftMinted = true;

        emit CertificateMinted(newTokenId, purchase.buyer, purchaseId, treeNationId);
    }

    /// @notice Mark purchase as processed by backend
    function markPurchaseProcessed(uint256 purchaseId) external onlyOwner {
        Purchase storage purchase = purchases[purchaseId];
        require(purchase.buyer != address(0), "Purchase not found");
        require(!purchase.processed, "Already processed");
        
        purchase.processed = true;
    }

    // ============ Watering Game (GameFi) ============

    /// @notice Daily watering - earn points based on trees owned + streak bonus
    function waterPlant() external whenNotPaused {
        UserPlant storage plant = userPlants[msg.sender];
        
        require(
            block.timestamp > plant.lastWaterTime + cooldownTime,
            "Cooldown not finished"
        );

        uint256 totalTrees = getTotalTreeCount(msg.sender);
        require(totalTrees > 0, "No trees to water. Claim free tree first!");

        // Streak: reset if missed more than 2x cooldown
        if (plant.lastWaterTime == 0) {
            plant.waterStreak = 1;
        } else if (block.timestamp > plant.lastWaterTime + (cooldownTime * 2)) {
            plant.waterStreak = 1;
        } else {
            plant.waterStreak += 1;
        }

        plant.lastWaterTime = block.timestamp;
        plant.totalWaterCount += 1;
        
        // Points = (base × trees) + streak bonus
        uint256 basePoints = pointsPerWater * totalTrees;
        uint256 streakBonus = 0;
        
        if (plant.waterStreak > 1) {
            uint256 streakDays = plant.waterStreak - 1;
            if (streakDays > maxStreakBonus) streakDays = maxStreakBonus;
            streakBonus = streakDays * streakBonusPoints;
        }
        
        uint256 totalPointsEarned = basePoints + streakBonus;
        userPoints[msg.sender] += totalPointsEarned;
        
        emit PlantWatered(
            msg.sender, 
            plant.waterStreak, 
            plant.totalWaterCount, 
            totalPointsEarned,
            userPoints[msg.sender],
            block.timestamp
        );
    }

    // ============ Admin Functions ============

    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender, block.timestamp);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender, block.timestamp);
    }

    function setCooldownTime(uint256 _seconds) external onlyOwner {
        require(_seconds > 0, "Must be > 0");
        uint256 old = cooldownTime;
        cooldownTime = _seconds;
        emit CooldownTimeUpdated(old, _seconds);
    }

    function setMinPurchaseAmount(uint256 _amount) external onlyOwner {
        uint256 old = minPurchaseAmount;
        minPurchaseAmount = _amount;
        emit MinPurchaseAmountUpdated(old, _amount);
    }

    function setPointsSettings(
        uint256 _pointsPerWater,
        uint256 _streakBonusPoints,
        uint256 _maxStreakBonus,
        uint256 _pointsPerVirtualTree
    ) external onlyOwner {
        pointsPerWater = _pointsPerWater;
        streakBonusPoints = _streakBonusPoints;
        maxStreakBonus = _maxStreakBonus;
        pointsPerVirtualTree = _pointsPerVirtualTree;
        
        emit PointsSettingsUpdated(_pointsPerWater, _streakBonusPoints, _maxStreakBonus, _pointsPerVirtualTree);
    }

    function awardPoints(address user, uint256 amount) external onlyOwner {
        userPoints[user] += amount;
    }

    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    // ============ View Functions ============

    function getTotalTreeCount(address user) public view returns (uint256) {
        uint256 realTrees = userPurchaseIds[user].length;
        uint256 virtualTrees = virtualTreeCount[user];
        return realTrees + virtualTrees;
    }

    function getUserForest(address user) external view returns (
        uint256 virtualTrees,
        uint256 realTrees,
        uint256 totalTrees,
        uint256 points,
        bool hasFreeTree
    ) {
        virtualTrees = virtualTreeCount[user];
        realTrees = userPurchaseIds[user].length;
        totalTrees = virtualTrees + realTrees;
        points = userPoints[user];
        hasFreeTree = hasClaimedFreeTree[user];
    }

    function getUserPlant(address user) external view returns (
        uint256 lastWaterTime,
        uint256 waterStreak,
        uint256 totalWaterCount
    ) {
        UserPlant storage plant = userPlants[user];
        return (plant.lastWaterTime, plant.waterStreak, plant.totalWaterCount);
    }

    function canWaterNow(address user) external view returns (bool canWater, uint256 timeRemaining) {
        UserPlant storage plant = userPlants[user];
        uint256 nextWaterTime = plant.lastWaterTime + cooldownTime;
        
        if (block.timestamp > nextWaterTime) {
            return (true, 0);
        } else {
            return (false, nextWaterTime - block.timestamp);
        }
    }

    function calculateWaterPoints(address user) external view returns (
        uint256 basePoints,
        uint256 streakBonus,
        uint256 totalPoints
    ) {
        UserPlant storage plant = userPlants[user];
        uint256 totalTrees = getTotalTreeCount(user);
        
        if (totalTrees == 0) {
            return (0, 0, 0);
        }
        
        basePoints = pointsPerWater * totalTrees;
        
        uint256 expectedStreak = plant.waterStreak;
        if (plant.lastWaterTime == 0 || block.timestamp > plant.lastWaterTime + (cooldownTime * 2)) {
            expectedStreak = 1;
        } else {
            expectedStreak += 1;
        }
        
        if (expectedStreak > 1) {
            uint256 streakDays = expectedStreak - 1;
            if (streakDays > maxStreakBonus) streakDays = maxStreakBonus;
            streakBonus = streakDays * streakBonusPoints;
        }
        
        totalPoints = basePoints + streakBonus;
    }

    function getPurchase(uint256 purchaseId) external view returns (
        address buyer,
        uint256 speciesId,
        uint256 projectId,
        uint256 amountPaid,
        uint256 timestamp,
        bool processed,
        bool nftMinted
    ) {
        Purchase storage p = purchases[purchaseId];
        return (p.buyer, p.speciesId, p.projectId, p.amountPaid, p.timestamp, p.processed, p.nftMinted);
    }

    function getUserPurchases(address user) external view returns (uint256[] memory) {
        return userPurchaseIds[user];
    }

    function getUserPurchaseCount(address user) external view returns (uint256) {
        return userPurchaseIds[user].length;
    }

    function getPointsSettings() external view returns (
        uint256 _pointsPerWater,
        uint256 _streakBonusPoints,
        uint256 _maxStreakBonus,
        uint256 _pointsPerVirtualTree
    ) {
        return (pointsPerWater, streakBonusPoints, maxStreakBonus, pointsPerVirtualTree);
    }

    function totalSupply() external view returns (uint256) {
        return _tokenIdCounter;
    }

    function totalPurchases() external view returns (uint256) {
        return _purchaseIdCounter;
    }

    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    // ============ Premium Virtual Tree ============

    /// @notice Purchase premium virtual trees with MNT
    function purchasePremiumVirtualTree(uint256 quantity) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
    {
        require(quantity > 0, "Quantity must be > 0");
        require(quantity <= MAX_PREMIUM_PER_TX, "Exceeds max per transaction");
        
        uint256 totalPrice = premiumTreePrice * quantity;
        require(msg.value >= totalPrice, "Insufficient payment");
        
        virtualTreeCount[msg.sender] += quantity;
        premiumTreeCount[msg.sender] += quantity;
        totalPremiumTrees += quantity;
        
        emit PremiumVirtualTreePurchased(
            msg.sender,
            quantity,
            msg.value,
            premiumTreeCount[msg.sender],
            block.timestamp
        );
        
        // Refund excess
        if (msg.value > totalPrice) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - totalPrice}("");
            require(success, "Refund failed");
        }

        (bool transferSuccess, ) = payable(owner()).call{value: totalPrice}("");
        require(transferSuccess, "Transfer to owner failed");
    }

    function setPremiumTreePrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be > 0");
        uint256 oldPrice = premiumTreePrice;
        premiumTreePrice = newPrice;
        emit PremiumTreePriceUpdated(oldPrice, newPrice);
    }

    function getUserPremiumTrees(address user) external view returns (uint256) {
        return premiumTreeCount[user];
    }

    function getPremiumTreeStats() external view returns (uint256 total, uint256 price) {
        return (totalPremiumTrees, premiumTreePrice);
    }
}

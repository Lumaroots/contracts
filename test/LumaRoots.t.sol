// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LumaRootsUpgradeable.sol";
import "../src/MockPriceFeed.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title LumaRootsTest
 * @notice Comprehensive test suite for LumaRoots protocol
 */
contract LumaRootsTest is Test {
    LumaRootsUpgradeable public implementation;
    LumaRootsUpgradeable public lumaRoots;
    MockPriceFeed public priceFeed;
    
    address public owner;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    uint256 constant INITIAL_BALANCE = 100 ether;

    // Allow test contract to receive ETH
    receive() external payable {}

    function setUp() public {
        owner = address(this);
        
        // Set block.timestamp to a realistic value (> 24 hours to pass cooldown check)
        vm.warp(100000000); // ~3 years from epoch
        
        // Deploy implementation
        implementation = new LumaRootsUpgradeable();
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            LumaRootsUpgradeable.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        lumaRoots = LumaRootsUpgradeable(address(proxy));
        
        // Deploy price feed
        priceFeed = new MockPriceFeed(1_00000000); // 1 USD = 1 MNT
        
        // Fund test accounts
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(charlie, INITIAL_BALANCE);
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertEq(lumaRoots.owner(), owner);
        assertEq(lumaRoots.VERSION(), "1.0.0");
        assertEq(lumaRoots.cooldownTime(), 24 hours);
        assertEq(lumaRoots.minPurchaseAmount(), 0.001 ether);
        assertEq(lumaRoots.pointsPerWater(), 10);
        assertEq(lumaRoots.streakBonusPoints(), 5);
        assertEq(lumaRoots.maxStreakBonus(), 7);
        assertEq(lumaRoots.pointsPerVirtualTree(), 500);
        assertEq(lumaRoots.premiumTreePrice(), 0.001 ether);
    }

    function test_CannotReinitialize() public {
        vm.expectRevert();
        lumaRoots.initialize(alice);
    }

    // ============ Free Tree Tests ============

    function test_ClaimFreeTree() public {
        vm.prank(alice);
        lumaRoots.claimFreeTree();
        
        assertEq(lumaRoots.virtualTreeCount(alice), 1);
        assertTrue(lumaRoots.hasClaimedFreeTree(alice));
        assertEq(lumaRoots.getTotalTreeCount(alice), 1);
    }

    function test_CannotClaimFreeTreeTwice() public {
        vm.startPrank(alice);
        lumaRoots.claimFreeTree();
        
        vm.expectRevert("Already claimed free tree");
        lumaRoots.claimFreeTree();
        vm.stopPrank();
    }

    function test_FreeTreeEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit LumaRootsUpgradeable.FreeTreeClaimed(alice, block.timestamp);
        
        vm.prank(alice);
        lumaRoots.claimFreeTree();
    }

    // ============ Watering Game Tests ============

    function test_WaterPlant() public {
        // Setup: claim free tree first
        vm.prank(alice);
        lumaRoots.claimFreeTree();
        
        // Warp time to ensure cooldown is ready (first water has no cooldown issue)
        vm.warp(block.timestamp + 1);
        
        // Water plant
        vm.prank(alice);
        lumaRoots.waterPlant();
        
        (uint256 lastWater, uint256 streak, uint256 totalCount) = lumaRoots.getUserPlant(alice);
        assertEq(streak, 1);
        assertEq(totalCount, 1);
        assertGt(lastWater, 0);
        assertEq(lumaRoots.userPoints(alice), 10); // 10 points for 1 tree
    }

    function test_CannotWaterWithoutTree() public {
        vm.prank(bob); // bob has no trees
        vm.expectRevert("No trees to water. Claim free tree first!");
        lumaRoots.waterPlant();
    }

    function test_WaterCooldown() public {
        vm.startPrank(alice);
        lumaRoots.claimFreeTree();
        
        vm.warp(block.timestamp + 1);
        lumaRoots.waterPlant();
        
        // Try to water again immediately
        vm.expectRevert("Cooldown not finished");
        lumaRoots.waterPlant();
        vm.stopPrank();
    }

    function test_WaterAfterCooldown() public {
        vm.startPrank(alice);
        lumaRoots.claimFreeTree();
        
        vm.warp(block.timestamp + 1);
        lumaRoots.waterPlant();
        
        // Advance time past cooldown
        vm.warp(block.timestamp + 24 hours + 1);
        
        lumaRoots.waterPlant();
        
        (, uint256 streak,) = lumaRoots.getUserPlant(alice);
        assertEq(streak, 2);
        vm.stopPrank();
    }

    function test_StreakBonus() public {
        vm.startPrank(alice);
        lumaRoots.claimFreeTree();
        
        // Day 1
        vm.warp(block.timestamp + 1);
        lumaRoots.waterPlant();
        assertEq(lumaRoots.userPoints(alice), 10); // base only
        
        // Day 2
        vm.warp(block.timestamp + 24 hours + 1);
        lumaRoots.waterPlant();
        assertEq(lumaRoots.userPoints(alice), 25); // 10 + (10 + 5 streak bonus)
        
        // Day 3
        vm.warp(block.timestamp + 24 hours + 1);
        lumaRoots.waterPlant();
        assertEq(lumaRoots.userPoints(alice), 45); // 25 + (10 + 10 streak bonus)
        
        vm.stopPrank();
    }

    function test_StreakResetAfterMiss() public {
        vm.startPrank(alice);
        lumaRoots.claimFreeTree();
        
        vm.warp(block.timestamp + 1);
        lumaRoots.waterPlant();
        
        // Day 2 - water
        vm.warp(block.timestamp + 24 hours + 1);
        lumaRoots.waterPlant();
        
        // Miss 2+ days (48+ hours)
        vm.warp(block.timestamp + 49 hours);
        lumaRoots.waterPlant();
        
        (, uint256 streak,) = lumaRoots.getUserPlant(alice);
        assertEq(streak, 1); // Reset to 1
        vm.stopPrank();
    }

    function test_MoreTreesMorePoints() public {
        vm.startPrank(alice);
        lumaRoots.claimFreeTree();
        
        // Buy 4 more premium trees (total 5)
        lumaRoots.purchasePremiumVirtualTree{value: 0.004 ether}(4);
        
        vm.warp(block.timestamp + 1);
        lumaRoots.waterPlant();
        assertEq(lumaRoots.userPoints(alice), 50); // 10 points × 5 trees
        vm.stopPrank();
    }

    function test_CanWaterNow() public {
        vm.startPrank(alice);
        lumaRoots.claimFreeTree();
        
        (bool canWater, uint256 remaining) = lumaRoots.canWaterNow(alice);
        assertTrue(canWater);
        assertEq(remaining, 0);
        
        vm.warp(block.timestamp + 1);
        lumaRoots.waterPlant();
        
        (canWater, remaining) = lumaRoots.canWaterNow(alice);
        assertFalse(canWater);
        assertGt(remaining, 0);
        vm.stopPrank();
    }

    // ============ Points Redemption Tests ============

    function test_RedeemPointsForTree() public {
        // Give alice 1000 points
        lumaRoots.awardPoints(alice, 1000);
        
        vm.prank(alice);
        lumaRoots.redeemPointsForTree(2); // 500 × 2 = 1000 points
        
        assertEq(lumaRoots.userPoints(alice), 0);
        assertEq(lumaRoots.virtualTreeCount(alice), 2);
    }

    function test_CannotRedeemWithInsufficientPoints() public {
        lumaRoots.awardPoints(alice, 400);
        
        vm.prank(alice);
        vm.expectRevert("Not enough points");
        lumaRoots.redeemPointsForTree(1);
    }

    function test_CannotRedeemZeroTrees() public {
        lumaRoots.awardPoints(alice, 1000);
        
        vm.prank(alice);
        vm.expectRevert("Must redeem at least 1 tree");
        lumaRoots.redeemPointsForTree(0);
    }

    // ============ Premium Tree Tests ============

    function test_PurchasePremiumTree() public {
        vm.prank(alice);
        lumaRoots.purchasePremiumVirtualTree{value: 0.001 ether}(1);
        
        assertEq(lumaRoots.virtualTreeCount(alice), 1);
        assertEq(lumaRoots.premiumTreeCount(alice), 1);
        assertEq(lumaRoots.totalPremiumTrees(), 1);
    }

    function test_PurchaseMultiplePremiumTrees() public {
        vm.prank(alice);
        lumaRoots.purchasePremiumVirtualTree{value: 0.005 ether}(5);
        
        assertEq(lumaRoots.virtualTreeCount(alice), 5);
        assertEq(lumaRoots.premiumTreeCount(alice), 5);
    }

    function test_PremiumTreeMaxPerTx() public {
        vm.prank(alice);
        vm.expectRevert("Exceeds max per transaction");
        lumaRoots.purchasePremiumVirtualTree{value: 0.011 ether}(11);
    }

    function test_PremiumTreeInsufficientPayment() public {
        vm.prank(alice);
        vm.expectRevert("Insufficient payment");
        lumaRoots.purchasePremiumVirtualTree{value: 0.0005 ether}(1);
    }

    function test_PremiumTreeRefundsExcess() public {
        uint256 balanceBefore = alice.balance;
        
        vm.prank(alice);
        lumaRoots.purchasePremiumVirtualTree{value: 0.01 ether}(1); // Overpay
        
        uint256 balanceAfter = alice.balance;
        assertEq(balanceBefore - balanceAfter, 0.001 ether); // Only charged correct amount
    }

    // ============ Real Tree Purchase Tests ============

    function test_PurchaseRealTree() public {
        uint256 ownerBalanceBefore = owner.balance;
        
        vm.prank(alice);
        lumaRoots.purchaseTree{value: 0.5 ether}(1, 1, 1);
        
        // Check purchase recorded
        (address buyer, uint256 speciesId, uint256 projectId, uint256 amount,,, ) = 
            lumaRoots.getPurchase(0);
        
        assertEq(buyer, alice);
        assertEq(speciesId, 1);
        assertEq(projectId, 1);
        assertEq(amount, 0.5 ether);
        assertEq(lumaRoots.getUserPurchaseCount(alice), 1);
        
        // Check funds transferred to owner
        assertEq(owner.balance, ownerBalanceBefore + 0.5 ether);
    }

    function test_PurchaseMultipleRealTrees() public {
        vm.prank(alice);
        lumaRoots.purchaseTree{value: 1 ether}(1, 1, 5);
        
        assertEq(lumaRoots.getUserPurchaseCount(alice), 5);
        assertEq(lumaRoots.totalPurchases(), 5);
    }

    function test_RealTreeMinimumAmount() public {
        vm.prank(alice);
        vm.expectRevert("Below minimum purchase amount");
        lumaRoots.purchaseTree{value: 0.0001 ether}(1, 1, 1);
    }

    function test_RealTreeInvalidQuantityZero() public {
        vm.prank(alice);
        vm.expectRevert("Quantity must be 1-100");
        lumaRoots.purchaseTree{value: 1 ether}(1, 1, 0);
    }

    function test_RealTreeInvalidQuantityTooMany() public {
        // 101 exceeds max quantity of 100
        vm.expectRevert("Quantity must be 1-100");
        vm.prank(alice);
        lumaRoots.purchaseTree{value: 10 ether}(1, 1, 101);
    }

    // ============ NFT Certificate Tests ============

    function test_MintCertificate() public {
        // Purchase tree
        vm.prank(alice);
        lumaRoots.purchaseTree{value: 0.5 ether}(1, 1, 1);
        
        // Mark as processed (simulating backend)
        lumaRoots.markPurchaseProcessed(0);
        
        // Mint certificate
        lumaRoots.mintCertificate(0, "ipfs://QmTest", "TN-123456");
        
        // Check NFT minted
        assertEq(lumaRoots.ownerOf(0), alice);
        assertEq(lumaRoots.totalSupply(), 1);
        
        // Check purchase marked as minted
        (,,,,,, bool nftMinted) = lumaRoots.getPurchase(0);
        assertTrue(nftMinted);
    }

    function test_CannotMintUnprocessedPurchase() public {
        vm.prank(alice);
        lumaRoots.purchaseTree{value: 0.5 ether}(1, 1, 1);
        
        vm.expectRevert("Purchase not yet processed");
        lumaRoots.mintCertificate(0, "ipfs://QmTest", "TN-123456");
    }

    function test_CannotMintTwice() public {
        vm.prank(alice);
        lumaRoots.purchaseTree{value: 0.5 ether}(1, 1, 1);
        
        lumaRoots.markPurchaseProcessed(0);
        lumaRoots.mintCertificate(0, "ipfs://QmTest", "TN-123456");
        
        vm.expectRevert("NFT already minted");
        lumaRoots.mintCertificate(0, "ipfs://QmTest", "TN-123456");
    }

    // ============ Admin Function Tests ============

    function test_Pause() public {
        lumaRoots.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        lumaRoots.claimFreeTree();
    }

    function test_Unpause() public {
        lumaRoots.pause();
        lumaRoots.unpause();
        
        vm.prank(alice);
        lumaRoots.claimFreeTree(); // Should work
    }

    function test_OnlyOwnerCanPause() public {
        vm.prank(alice);
        vm.expectRevert();
        lumaRoots.pause();
    }

    function test_SetCooldownTime() public {
        lumaRoots.setCooldownTime(12 hours);
        assertEq(lumaRoots.cooldownTime(), 12 hours);
    }

    function test_SetMinPurchaseAmount() public {
        lumaRoots.setMinPurchaseAmount(0.01 ether);
        assertEq(lumaRoots.minPurchaseAmount(), 0.01 ether);
    }

    function test_SetPointsSettings() public {
        lumaRoots.setPointsSettings(20, 10, 14, 1000);
        
        (uint256 perWater, uint256 streakBonus, uint256 maxStreak, uint256 redeemCost) = 
            lumaRoots.getPointsSettings();
        
        assertEq(perWater, 20);
        assertEq(streakBonus, 10);
        assertEq(maxStreak, 14);
        assertEq(redeemCost, 1000);
    }

    function test_SetPremiumTreePrice() public {
        lumaRoots.setPremiumTreePrice(0.01 ether);
        assertEq(lumaRoots.premiumTreePrice(), 0.01 ether);
    }

    function test_AwardPoints() public {
        lumaRoots.awardPoints(alice, 500);
        assertEq(lumaRoots.userPoints(alice), 500);
    }

    function test_EmergencyWithdraw() public {
        // Send some ETH to contract (shouldn't happen normally, but just in case)
        vm.deal(address(lumaRoots), 1 ether);
        
        uint256 ownerBalanceBefore = owner.balance;
        lumaRoots.emergencyWithdraw();
        
        assertEq(owner.balance, ownerBalanceBefore + 1 ether);
        assertEq(address(lumaRoots).balance, 0);
    }

    // ============ View Function Tests ============

    function test_GetUserForest() public {
        vm.startPrank(alice);
        lumaRoots.claimFreeTree();
        lumaRoots.purchasePremiumVirtualTree{value: 0.002 ether}(2);
        vm.stopPrank();
        
        lumaRoots.awardPoints(alice, 100);
        
        (uint256 vTrees, uint256 rTrees, uint256 total, uint256 points, bool hasFree) = 
            lumaRoots.getUserForest(alice);
        
        assertEq(vTrees, 3);
        assertEq(rTrees, 0);
        assertEq(total, 3);
        assertEq(points, 100);
        assertTrue(hasFree);
    }

    function test_CalculateWaterPoints() public {
        vm.startPrank(alice);
        lumaRoots.claimFreeTree();
        lumaRoots.purchasePremiumVirtualTree{value: 0.004 ether}(4); // 5 trees total
        
        vm.warp(block.timestamp + 1);
        lumaRoots.waterPlant();
        
        vm.warp(block.timestamp + 24 hours + 1);
        
        (uint256 basePoints, uint256 streakBonus, uint256 totalPoints) = 
            lumaRoots.calculateWaterPoints(alice);
        
        assertEq(basePoints, 50); // 10 × 5 trees
        assertEq(streakBonus, 5); // streak day 2 = 1 × 5
        assertEq(totalPoints, 55);
        vm.stopPrank();
    }

    function test_GetPremiumTreeStats() public {
        vm.prank(alice);
        lumaRoots.purchasePremiumVirtualTree{value: 0.003 ether}(3);
        
        vm.prank(bob);
        lumaRoots.purchasePremiumVirtualTree{value: 0.002 ether}(2);
        
        (uint256 total, uint256 price) = lumaRoots.getPremiumTreeStats();
        assertEq(total, 5);
        assertEq(price, 0.001 ether);
    }

    // ============ Integration Tests ============

    function test_FullUserJourney() public {
        // Alice's journey through LumaRoots
        vm.startPrank(alice);
        
        // 1. Claim free tree
        lumaRoots.claimFreeTree();
        assertEq(lumaRoots.getTotalTreeCount(alice), 1);
        
        // 2. Water daily for a week
        vm.warp(block.timestamp + 1);
        for (uint i = 0; i < 7; i++) {
            lumaRoots.waterPlant();
            vm.warp(block.timestamp + 24 hours + 1);
        }
        
        // 3. Water more to accumulate 500+ points
        for (uint i = 0; i < 14; i++) {
            lumaRoots.waterPlant();
            vm.warp(block.timestamp + 24 hours + 1);
        }
        
        // Check points > 500
        assertGt(lumaRoots.userPoints(alice), 500);
        
        // 4. Redeem for virtual tree
        lumaRoots.redeemPointsForTree(1);
        assertEq(lumaRoots.virtualTreeCount(alice), 2); // 1 free + 1 redeemed
        
        // 5. Buy premium tree
        lumaRoots.purchasePremiumVirtualTree{value: 0.001 ether}(1);
        assertEq(lumaRoots.virtualTreeCount(alice), 3);
        
        // 6. Donate for real tree
        lumaRoots.purchaseTree{value: 1 ether}(123, 456, 1);
        assertEq(lumaRoots.getUserPurchaseCount(alice), 1);
        
        vm.stopPrank();
        
        // 7. Backend processes and mints NFT
        lumaRoots.markPurchaseProcessed(0);
        lumaRoots.mintCertificate(0, "ipfs://QmAliceTree", "TN-ALICE-001");
        
        // Final state
        assertEq(lumaRoots.ownerOf(0), alice);
        assertEq(lumaRoots.getTotalTreeCount(alice), 4); // 3 virtual + 1 real
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MockPriceFeed.sol";

/**
 * @title MockPriceFeedTest
 * @notice Test suite for MockPriceFeed oracle
 */
contract MockPriceFeedTest is Test {
    MockPriceFeed public priceFeed;
    
    address public owner = address(this);
    address public alice = address(0x1);
    
    int256 constant INITIAL_PRICE = 1_00000000; // 1 USD = 1 MNT

    function setUp() public {
        priceFeed = new MockPriceFeed(INITIAL_PRICE);
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertEq(priceFeed.latestAnswer(), INITIAL_PRICE);
        assertEq(priceFeed.decimals(), 8);
        assertEq(priceFeed.description(), "USD / MNT");
        assertEq(priceFeed.owner(), owner);
    }

    function test_CannotInitializeWithZeroPrice() public {
        vm.expectRevert("Price must be positive");
        new MockPriceFeed(0);
    }

    function test_CannotInitializeWithNegativePrice() public {
        vm.expectRevert("Price must be positive");
        new MockPriceFeed(-1);
    }

    // ============ Chainlink Interface Tests ============

    function test_LatestRoundData() public view {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        
        assertEq(roundId, 1);
        assertEq(answer, INITIAL_PRICE);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }

    function test_LatestAnswer() public view {
        assertEq(priceFeed.latestAnswer(), INITIAL_PRICE);
    }

    function test_Decimals() public view {
        assertEq(priceFeed.decimals(), 8);
    }

    // ============ Price Update Tests ============

    function test_UpdatePrice() public {
        int256 newPrice = 2_00000000; // 2 USD = 1 MNT
        priceFeed.updatePrice(newPrice);
        
        assertEq(priceFeed.latestAnswer(), newPrice);
    }

    function test_UpdatePriceEmitsEvent() public {
        int256 newPrice = 2_00000000;
        
        vm.expectEmit(false, false, false, true);
        emit MockPriceFeed.PriceUpdated(INITIAL_PRICE, newPrice, block.timestamp);
        
        priceFeed.updatePrice(newPrice);
    }

    function test_CannotUpdatePriceToZero() public {
        vm.expectRevert("Price must be positive");
        priceFeed.updatePrice(0);
    }

    function test_OnlyOwnerCanUpdatePrice() public {
        vm.prank(alice);
        vm.expectRevert();
        priceFeed.updatePrice(2_00000000);
    }

    // ============ Conversion Tests ============

    function test_UsdToMnt_OneToOne() public view {
        // At 1:1 rate, 1 USD = 1 MNT
        uint256 usdAmount = 1 ether; // 1 USD in wei
        uint256 mntAmount = priceFeed.usdToMnt(usdAmount);
        
        assertEq(mntAmount, 1 ether);
    }

    function test_UsdToMnt_DifferentRate() public {
        // Set rate to 0.5 USD = 1 MNT (MNT is worth more)
        priceFeed.updatePrice(50000000); // 0.5 with 8 decimals
        
        uint256 usdAmount = 1 ether;
        uint256 mntAmount = priceFeed.usdToMnt(usdAmount);
        
        assertEq(mntAmount, 0.5 ether);
    }

    function test_MntToUsd_OneToOne() public view {
        uint256 mntAmount = 1 ether;
        uint256 usdAmount = priceFeed.mntToUsd(mntAmount);
        
        assertEq(usdAmount, 1 ether);
    }

    function test_MntToUsd_DifferentRate() public {
        // Set rate to 2 USD = 1 MNT
        priceFeed.updatePrice(2_00000000);
        
        uint256 mntAmount = 1 ether;
        uint256 usdAmount = priceFeed.mntToUsd(mntAmount);
        
        assertEq(usdAmount, 0.5 ether);
    }

    function test_GetRequiredMnt() public view {
        // 1500 cents = $15.00
        uint256 priceInCents = 1500;
        uint256 requiredMnt = priceFeed.getRequiredMnt(priceInCents);
        
        // At 1:1 rate, $15 = 15 MNT
        assertEq(requiredMnt, 15 ether);
    }

    function test_GetRequiredMnt_SmallAmount() public view {
        // 100 cents = $1.00
        uint256 requiredMnt = priceFeed.getRequiredMnt(100);
        assertEq(requiredMnt, 1 ether);
    }

    function test_GetRequiredMnt_DifferentRate() public {
        // Set rate to 2 USD = 1 MNT
        priceFeed.updatePrice(2_00000000);
        
        // $10 should require 20 MNT at this rate
        uint256 requiredMnt = priceFeed.getRequiredMnt(1000); // $10
        assertEq(requiredMnt, 20 ether);
    }

    // ============ Fuzz Tests ============

    function testFuzz_UpdatePrice(int256 newPrice) public {
        vm.assume(newPrice > 0);
        vm.assume(newPrice < type(int256).max / 1e18); // Prevent overflow
        
        priceFeed.updatePrice(newPrice);
        assertEq(priceFeed.latestAnswer(), newPrice);
    }

    function testFuzz_UsdToMnt(uint256 usdAmount) public view {
        vm.assume(usdAmount < type(uint256).max / uint256(INITIAL_PRICE));
        
        uint256 mntAmount = priceFeed.usdToMnt(usdAmount);
        // At 1:1, should be equal
        assertEq(mntAmount, usdAmount);
    }
}

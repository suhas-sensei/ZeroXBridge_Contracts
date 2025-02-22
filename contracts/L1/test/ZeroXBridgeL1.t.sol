// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ZeroXBridgeL1} from "../src/ZeroXBridgeL1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {MockERC20} from "./mocks/MockERC20.sol";

// Test contract for AssetPricer
contract ZeroXBridgeL1Test is Test {
    ZeroXBridgeL1 public assetPricer;
    MockERC20 public dai;
    MockERC20 public usdc;
    address public ethPriceFeed;
    address public daiPriceFeed;
    address public usdcPriceFeed;

    function setUp() public {
    // Deploy the AssetPricer contract
    assetPricer = new ZeroXBridgeL1();

    // Deploy mock ERC20 tokens
    dai = new MockERC20(18); // DAI with 18 decimals
    usdc = new MockERC20(6); // USDC with 6 decimals

    // Assign mock price feed addresses
    ethPriceFeed = address(1);
    daiPriceFeed = address(2);
    usdcPriceFeed = address(3);

    // Add supported tokens with their price feeds and decimals
    assetPricer.addSupportedToken(address(0), ethPriceFeed, 18); // ETH
    assetPricer.addSupportedToken(address(dai), daiPriceFeed, 18); // DAI
    assetPricer.addSupportedToken(address(usdc), usdcPriceFeed, 6); // USDC
}

    /** Test Case 1: Happy Path - Calculate TVL with ETH and ERC20 tokens */
    function testUpdateAssetPricingHappyPath() public {
        // Fund the contract with ETH
        vm.deal(address(assetPricer), 1 ether); // 1 ETH = 1e18 wei

        // Mint DAI and USDC to the contract
        dai.mint(address(assetPricer), 1000 * 10**18); // 1000 DAI
        usdc.mint(address(assetPricer), 500 * 10**6); // 500 USDC

        // Mock Chainlink price feeds (prices in USD with 8 decimals)
        // ETH price: $2000 = 2000 * 10^8
        vm.mockCall(
            ethPriceFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(2000 * 10**8), uint256(0), uint256(0), uint80(0))
        );
        // DAI price: $1 = 1 * 10^8
        vm.mockCall(
            daiPriceFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(1 * 10**8), uint256(0), uint256(0), uint80(0))
        );
        // USDC price: $1 = 1 * 10^8
        vm.mockCall(
            usdcPriceFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(1 * 10**8), uint256(0), uint256(0), uint80(0))
        );

        // Call update_asset_pricing
        assetPricer.update_asset_pricing();

        // Calculate expected TVL (in USD with 18 decimals)
        // ETH: 1 ETH * $2000 = $2000 = 2000e18
        // DAI: 1000 DAI * $1 = $1000 = 1000e18
        // USDC: 500 USDC * $1 = $500 = 500e18
        // Total TVL = 2000e18 + 1000e18 + 500e18 = 3500e18
        uint256 expectedTvl = 3500 * 10**18;
        assertEq(assetPricer.tvl(), expectedTvl, "TVL should match expected value");
    }

    /** Test Case 2: Zero Balance - Tokens with zero balance contribute nothing to TVL */
    function testUpdateAssetPricingZeroBalance() public {
        // Fund the contract with ETH
        vm.deal(address(assetPricer), 1 ether); // 1 ETH

        // Mint DAI but not USDC (USDC balance = 0)
        dai.mint(address(assetPricer), 1000 * 10**18); // 1000 DAI

        // Mock price feeds
        vm.mockCall(
            ethPriceFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(2000 * 10**8), uint256(0), uint256(0), uint80(0))
        );
        vm.mockCall(
            daiPriceFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(1 * 10**8), uint256(0), uint256(0), uint80(0))
        );
        vm.mockCall(
            usdcPriceFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(1 * 10**8), uint256(0), uint256(0), uint80(0))
        );

        // Call update_asset_pricing
        assetPricer.update_asset_pricing();

        // Expected TVL: 2000e18 (ETH) + 1000e18 (DAI) + 0 (USDC) = 3000e18
        uint256 expectedTvl = 3000 * 10**18;
        assertEq(assetPricer.tvl(), expectedTvl, "TVL should exclude zero-balance tokens");
    }

    /** Test Case 3: Missing Price Feed - Reverts if a token lacks a price feed */
 function testUpdateAssetPricingMissingPriceFeed() public {
    // Add a token without a price feed
    address tokenWithoutFeed = address(4);
    assetPricer.addSupportedToken(tokenWithoutFeed, address(0), 18);

    // Mock price feeds for existing tokens (ETH, DAI, USDC)
    vm.mockCall(
        address(1), // ethPriceFeed
        abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
        abi.encode(uint80(1), int256(2000 * 10**8), uint256(0), uint256(0), uint80(0))
    );
    vm.mockCall(
        address(2), // daiPriceFeed
        abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
        abi.encode(uint80(1), int256(1 * 10**8), uint256(0), uint256(0), uint80(0))
    );
    vm.mockCall(
        address(3), // usdcPriceFeed
        abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
        abi.encode(uint80(1), int256(1 * 10**8), uint256(0), uint256(0), uint80(0))
    );

    // Expect revert with the specific message
    vm.expectRevert("No price feed for token");
    assetPricer.update_asset_pricing();
}
    /** Test Case 4: Invalid Price - Reverts if a price feed returns zero or negative */
    function testUpdateAssetPricingInvalidPrice() public {
        // Fund the contract to ensure it processes the price feed
        vm.deal(address(assetPricer), 1 ether);

        // Mock ETH price feed to return 0
        vm.mockCall(
            ethPriceFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(0), uint256(0), uint256(0), uint80(0))
        );

        // Expect revert
        vm.expectRevert("Invalid price");
        assetPricer.update_asset_pricing();
    }

    /** Test Case 5: Empty Supported Tokens - TVL is zero when no tokens are supported */
    function testUpdateAssetPricingEmptySupportedTokens() public {
        // Deploy a new AssetPricer with no supported tokens
        ZeroXBridgeL1 newAssetPricer = new ZeroXBridgeL1();

        // Call update_asset_pricing
        newAssetPricer.update_asset_pricing();

        // TVL should be 0
        assertEq(newAssetPricer.tvl(), 0, "TVL should be zero with no supported tokens");
    }
}
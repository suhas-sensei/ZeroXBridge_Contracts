// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Chainlink price feed interface
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ZeroXBridgeL1 {
    // Storage variables
    uint256 public tvl; // Total Value Locked in USD, with 18 decimals
    mapping(address => address) public priceFeeds; // Maps token address to Chainlink price feed address
    address[] public supportedTokens; // List of token addresses, including address(0) for ETH
    mapping(address => uint8) public tokenDecimals; // Maps token address to its decimals


     function addSupportedToken(address token, address priceFeed, uint8 decimals) external {
        supportedTokens.push(token);
        priceFeeds[token] = priceFeed;
        tokenDecimals[token] = decimals;
    }


    function update_asset_pricing() external {
        uint256 totalValue = 0;

        // Iterate through all supported tokens, including ETH
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address tokenAddress = supportedTokens[i];
            uint256 balance;
            uint256 dec;
            uint256 price;

            // Get balance and decimals
            if (tokenAddress == address(0)) {
                balance = address(this).balance; // ETH balance in wei
                dec = tokenDecimals[tokenAddress]; // Should be 18 for ETH
            } else {
                IERC20 token = IERC20(tokenAddress);
                balance = token.balanceOf(address(this)); // Token balance in smallest units
                dec = tokenDecimals[tokenAddress]; // Use stored decimals
            }

            // Fetch price from Chainlink price feed
            address feedAddress = priceFeeds[tokenAddress];
            require(feedAddress != address(0), "No price feed for token");
            AggregatorV3Interface priceFeed = AggregatorV3Interface(feedAddress);
            (, int256 priceInt,,,) = priceFeed.latestRoundData();
            require(priceInt > 0, "Invalid price");
            price = uint256(priceInt); // Price in USD with 8 decimals

            // Calculate USD value with 18 decimals
            // value = (balance * price * 10^18) / (10^dec * 10^8)
            // To minimize overflow, compute in steps
            uint256 temp = (balance * price) / 1e8;
            uint256 value = (temp * 1e18) / (10 ** dec);
            totalValue += value;
        }

        // Update TVL
        tvl = totalValue;
    }
}
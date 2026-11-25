// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract PriceOracle is Ownable {
    // eg: WETH address => WETH/USD feed
    mapping(address tokenAddress => address priceFeedAddress) public priceFeeds;
    uint256 private constant WAD = 1e18;

    error ZeroAddress();
    error InvalidPrice();
    error PriceFeedNotFound();

    constructor() Ownable(msg.sender) {}

    function setPriceFeed(address _tokenAddress, address _priceFeedAddress) public onlyOwner {
        if (_tokenAddress == address(0) || _priceFeedAddress == address(0)) {
            revert ZeroAddress();
        }
        priceFeeds[_tokenAddress] = _priceFeedAddress;
    }

    function getPrice(address _tokenAddress) external view returns (uint256 price) {
        if (priceFeeds[_tokenAddress] == address(0)) {
            revert PriceFeedNotFound();
        }

        (, int256 answer,,,) = AggregatorV3Interface(priceFeeds[_tokenAddress]).latestRoundData();
        if (answer <= 0) {
            revert InvalidPrice();
        }
        uint8 decimal = AggregatorV3Interface(priceFeeds[_tokenAddress]).decimals();
        price = (uint256(answer) * 10 ** (18 - decimal));
    }
}

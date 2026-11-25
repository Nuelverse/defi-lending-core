// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

contract MockAggregator {
    // mock aggregator to run test
    uint8 private feedDecimals;
    int256 private answer;
    uint80 private roundId;
    uint256 private updatedAt;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        feedDecimals = _decimals;
        answer = _initialAnswer;
        updatedAt = block.timestamp;
        roundId = 1;
    }

    function decimals() external view returns (uint8) {
        return feedDecimals;
    }

    function description() external pure returns (string memory) {
        return "Mock Chainlink Price Feed";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId) external view returns (uint80, int256, uint256, uint256, uint80) {
        require(_roundId == roundId, "Round not found");

        return (roundId, answer, updatedAt, updatedAt, roundId);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, updatedAt, updatedAt, roundId);
    }

    function setAnswer(int256 _newAnswer) external {
        answer = _newAnswer;
        updatedAt = block.timestamp;
        roundId++;
    }

    function setUpdatedAt(uint256 _newTimestamp) external {
        updatedAt = _newTimestamp;
    }
}

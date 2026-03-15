// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockV3Aggregator is AggregatorV3Interface {
    uint8 private immutable i_decimals;
    int256 private s_answer;
    uint80 private s_roundId;

    constructor(uint8 decimals_, int256 initialAnswer) {
        i_decimals = decimals_;
        updateAnswer(initialAnswer);
    }

    function updateAnswer(int256 newAnswer) public {
        s_answer = newAnswer;
        s_roundId++;
    }

    function decimals() external view returns (uint8) {
        return i_decimals;
    }

    function description() external pure returns (string memory) {
        return "mock aggregator";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 roundId) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, s_answer, block.timestamp, block.timestamp, roundId);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (s_roundId, s_answer, block.timestamp, block.timestamp, s_roundId);
    }
}

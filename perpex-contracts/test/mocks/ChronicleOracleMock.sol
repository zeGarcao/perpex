// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IChronicleOracle} from "../../src/interfaces/IChronicleOracle.sol";

contract ChronicleOracleMock is IChronicleOracle {
    uint256 private _price;

    constructor(uint256 price) {
        _price = price;
    }

    function setPrice(uint256 price) external {
        _price = price;
    }

    function read() external view returns (uint256) {
        return _price;
    }
}

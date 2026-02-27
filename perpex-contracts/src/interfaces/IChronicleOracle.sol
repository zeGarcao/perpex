// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

interface IChronicleOracle {
    function read() external view returns (uint256);
}

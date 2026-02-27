// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

// TODO: open position
// TODO: close position
// TODO: increase position size
// TODO: decrease position size
// TODO: increase position collateral
// TODO: decrease position collateral
// TODO: liquidate position

interface IPerpex {
    event PositionOpened(bytes32 indexed id, address indexed owner);

    enum PositionSide {
        LONG,
        SHORT
    }

    struct Position {
        address owner;
        address token;
        uint256 collateral;
        uint256 size;
        uint256 sizeInTokens;
        PositionSide side;
    }

    function openPosition(address token, uint256 collateral, uint256 size, PositionSide side) external returns (bytes32);
}

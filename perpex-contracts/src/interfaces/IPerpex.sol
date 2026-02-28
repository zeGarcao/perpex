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

    struct OpenInterest {
        uint256 value; // 18 decimals (match chronicle prices)
        uint256 tokens; // token's native decimals
    }

    struct Position {
        address owner;
        address token;
        uint256 collateral; // 6 decimals (USDC)
        uint256 size; // 18 decimals (match chronicle prices)
        uint256 sizeInTokens; // token's native decimals
        PositionSide side;
        bool isOpen;
    }

    function openPosition(address token, uint256 collateral, uint256 size, PositionSide side) external returns (bytes32);

    function pnl() external view returns (int256);
}

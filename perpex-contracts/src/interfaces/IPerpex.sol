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
    event PositionSizeIncreased(bytes32 indexed id, uint256 amount);
    event PositionCollateralIncreased(bytes32 indexed id, uint256 amount);

    error PERPEX__TOKEN_NOT_ALLOWED();
    error PERPEX__INVALID_POSITION_SIZE();
    error PERPEX__INSUFFICIENT_COLLATERAL();
    error PERPEX__LEVERAGE_OUT_OF_BOUNDS();
    error PERPEX__POSITION_NOT_FOUND();
    error PERPEX__NOT_POSITION_OWNER();
    error PERPEX__POSITION_ALREADY_CLOSED();
    error PERPEX__LIQUIDATABLE_POSITION();

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

    function increasePositionSize(bytes32 id, uint256 size) external;

    function increasePositionCollateral(bytes32 id, uint256 collateral) external;

    function totalPnL() external view returns (int256);

    function positionPnL(bytes32 id) external view returns (int256);

    function isPositionLiquidatable(bytes32 id) external view returns (bool);

    function totalOpenInterest() external view returns (uint256);
}

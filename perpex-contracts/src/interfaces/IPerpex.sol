// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

// TODO: open position
// TODO: close position
// TODO: increase position size
// TODO: decrease position size
// TODO: increase position collateral
// TODO: decrease position collateral
// TODO: liquidate position

/// @title IPerpex
/// @notice Interface for the Perpex perpetual exchange protocol
/// @dev Manages leveraged long and short positions with USDC collateral
interface IPerpex {
    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Emitted when a new position is opened
     * @param id The unique identifier of the position
     * @param owner The address of the position owner
     */
    event PositionOpened(bytes32 indexed id, address indexed owner);

    /**
     * @notice Emitted when a position's size is increased
     * @param id The unique identifier of the position
     * @param amount The amount by which the position size was increased (18 decimals)
     */
    event PositionSizeIncreased(bytes32 indexed id, uint256 amount);

    /**
     * @notice Emitted when a position's collateral is increased
     * @param id The unique identifier of the position
     * @param amount The amount of collateral added (6 decimals - USDC)
     */
    event PositionCollateralIncreased(bytes32 indexed id, uint256 amount);

    /**
     * @notice Emitted when the minimum leverage is updated
     * @param minLeverage The new minimum leverage value
     */
    event MinLeverageUpdated(uint256 minLeverage);

    /**
     * @notice Emitted when the maximum leverage is updated
     * @param maxLeverage The new maximum leverage value
     */
    event MaxLeverageUpdated(uint256 maxLeverage);

    /**
     * @notice Emitted when the position fee is updated
     * @param positionFee The new position fee
     */
    event PositionFeeUpdated(uint256 positionFee);

    /**
     * @notice Emitted when the liquidation threshold is updated
     * @param liquidationThreshold The new liquidation threshold
     */
    event LiquidationThresholdUpdated(uint256 liquidationThreshold);

    /**
     * @notice Emitted when a new token is added to the allowed trading tokens
     * @param token The address of the token
     * @param oracle The address of the oracle for the token
     */
    event TokenAdded(address indexed token, address oracle);

    /**
     * @notice Emitted when a token is removed from allowed trading tokens
     * @param token The address of the token
     */
    event TokenRemoved(address indexed token);

    //////////////////////////////////////////////////////////////
    //                          ERRORS                          //
    //////////////////////////////////////////////////////////////

    /// @notice Thrown when a zero address is provided where it's not allowed
    error PERPEX__ZERO_ADDRESS();

    /// @notice Thrown when an invalid token address is provided
    error PERPEX__INVALID_TOKEN();

    /// @notice Thrown when the minimum leverage value is invalid
    error PERPEX__INVALID_MIN_LEVERAGE();

    /// @notice Thrown when the maximum leverage value is invalid
    error PERPEX__INVALID_MAX_LEVERAGE();

    /// @notice Thrown when the liquidation threshold is invalid
    error PERPEX__INVALID_LIQUIDATION_THRESHOLD();

    /// @notice Thrown when attempting to trade a token that is not allowed
    error PERPEX__TOKEN_NOT_ALLOWED();

    /// @notice Thrown when the position size is invalid
    error PERPEX__INVALID_POSITION_SIZE();

    /// @notice Thrown when there is insufficient collateral for the operation
    error PERPEX__INSUFFICIENT_COLLATERAL();

    /// @notice Thrown when the leverage is outside the allowed bounds
    error PERPEX__LEVERAGE_OUT_OF_BOUNDS();

    /// @notice Thrown when attempting to access a position that doesn't exist
    error PERPEX__POSITION_NOT_FOUND();

    /// @notice Thrown when a non-owner attempts to modify a position
    error PERPEX__NOT_POSITION_OWNER();

    /// @notice Thrown when attempting to operate on an already closed position
    error PERPEX__POSITION_ALREADY_CLOSED();

    /// @notice Thrown when attempting to increase a position that is already liquidatable
    error PERPEX__LIQUIDATABLE_POSITION();

    //////////////////////////////////////////////////////////////
    //                       DATA TYPES                         //
    //////////////////////////////////////////////////////////////

    /// @notice Enum representing the side of a position
    enum PositionSide {
        LONG,
        SHORT
    }

    /// @notice Struct representing the open interest for a token
    struct OpenInterest {
        uint256 value; /// @notice Total open interest value in USD (18 decimals, matching Chronicle oracle prices)
        uint256 tokens; /// @notice Total open interest in token amounts (token's native decimals)
    }

    /// @notice Struct representing a trading position
    struct Position {
        address owner; /// @notice Address of the position owner
        address token; /// @notice Address of the token being traded
        uint256 collateral; /// @notice Collateral amount in USDC (6 decimals)
        uint256 size; /// @notice Position size in USD value (18 decimals, matching Chronicle oracle prices)
        uint256 sizeInTokens; /// @notice Position size in token amounts (token's native decimals)
        PositionSide side; /// @notice Side of the position (LONG or SHORT)
        bool isOpen; /// @notice Whether the position is currently open
    }

    //////////////////////////////////////////////////////////////
    //                        FUNCTIONS                         //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Opens a new leveraged position
     * @param token The address of the token to trade
     * @param collateral The amount of USDC collateral to provide (6 decimals)
     * @param size The size of the position in USD value (18 decimals)
     * @param side The side of the position (LONG or SHORT)
     * @return The unique identifier of the newly opened position
     */
    function openPosition(address token, uint256 collateral, uint256 size, PositionSide side) external returns (bytes32);

    /**
     * @notice Increases the size of an existing position
     * @param id The unique identifier of the position
     * @param size The amount to increase the position size by (18 decimals)
     */
    function increasePositionSize(bytes32 id, uint256 size) external;

    /**
     * @notice Increases the collateral of an existing position
     * @param id The unique identifier of the position
     * @param collateral The amount of collateral to add (6 decimals - USDC)
     */
    function increasePositionCollateral(bytes32 id, uint256 collateral) external;

    /**
     * @notice Calculates the total profit and loss across all positions
     * @return The total PnL in USDC (6 decimals), can be negative
     */
    function totalPnL() external view returns (int256);

    /**
     * @notice Calculates the profit and loss for a specific position
     * @param id The unique identifier of the position
     * @return The PnL for the position in USDC (6 decimals), can be negative
     */
    function positionPnL(bytes32 id) external view returns (int256);

    /**
     * @notice Checks if a position is eligible for liquidation
     * @param id The unique identifier of the position
     * @return True if the position can be liquidated, false otherwise
     */
    function isPositionLiquidatable(bytes32 id) external view returns (bool);

    /**
     * @notice Calculates the total open interest across all positions
     * @return The total open interest in USD value (18 decimals)
     */
    function totalOpenInterest() external view returns (uint256);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

// TODO: add liquidity
// TODO: remove liquidity

/// @title IPool
/// @notice Interface for the Perpex liquidity pool
/// @dev Manages reserve accounting and available assets for the Perpex protocol
interface IPool {
    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Emitted when assets are reserved for position backing
     * @param assets The amount of assets reserved (6 decimals - USDC)
     */
    event AssetsReserved(uint256 assets);

    /**
     * @notice Emitted when previously reserved assets are released
     * @param assets The amount of assets released (6 decimals - USDC)
     */
    event AssetsReleased(uint256 assets);

    /**
     * @notice Emitted when the maximum utilization ratio is updated
     * @param maxUtilization The new max utilization ratio (18 decimals)
     */
    event MaxUtilizationUpdated(uint256 maxUtilization);

    //////////////////////////////////////////////////////////////
    //                          ERRORS                          //
    //////////////////////////////////////////////////////////////

    /// @notice Thrown when a non-Perpex caller tries to invoke a Perpex-only function
    error POOL__ONLY_PERPEX();

    /// @notice Thrown when a zero address is provided where it is not allowed
    error POOL__ZERO_ADDRESS();

    /// @notice Thrown when max utilization is outside valid bounds
    error POOL__INVALID_MAX_UTILIZATION();

    /// @notice Thrown when reserving assets would exceed max utilization
    error POOL__MAX_UTILIZATION_EXCEEDED();

    /// @notice Thrown when attempting to release an invalid amount of reserved assets
    error POOL__INVALID_RELEASE_AMOUNT();

    /// @notice Thrown when attempting to reserve an invalid amount of assets
    error POOL__INVALID_RESERVE_AMOUNT();

    //////////////////////////////////////////////////////////////
    //                        FUNCTIONS                         //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Reserves pool assets for open positions
     * @param assets The amount of assets to reserve (6 decimals - USDC)
     */
    function reserveAssets(uint256 assets) external;

    /**
     * @notice Releases previously reserved pool assets
     * @param assets The amount of assets to release (6 decimals - USDC)
     */
    function releaseAssets(uint256 assets) external;

    /**
     * @notice Returns currently available (unreserved) pool assets
     * @return The amount of available assets (6 decimals - USDC)
     */
    function availableAssets() external view returns (uint256);
}

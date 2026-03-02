// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

// TODO: add liquidity
// TODO: remove liquidity

interface IPool {
    event AssetsReserved(uint256 assets);
    event AssetsReleased(uint256 assets);

    error POOL__ONLY_PERPEX();
    error POOL__MAX_UTILIZATION_EXCEEDED();
    error POOL__INVALID_RELEASE_AMOUNT();

    function reserveAssets(uint256 assets) external;

    function releaseAssets(uint256 assets) external;

    function availableAssets() external view returns (uint256);
}

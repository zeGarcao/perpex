// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IPool} from "./interfaces/IPool.sol";
import {IPerpex} from "./interfaces/IPerpex.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Pool is IPool, ERC4626 {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 private constant WAD = 1e18;

    address private _perpex;
    uint256 private _reservedAssets;
    uint256 private _maxUtilization;

    constructor(address asset_) ERC4626(IERC20(asset_)) ERC20("Perpex Pool Token", "PPT") {}

    function reserveAssets(uint256 assets) external {
        require(msg.sender == _perpex, POOL__ONLY_PERPEX());

        _reservedAssets += assets;

        uint256 balance = ERC20(asset()).balanceOf(address(this)) * 1e12;
        int256 pnl = IPerpex(_perpex).pnl();

        if (pnl > balance.toInt256()) {
            balance = 0;
        } else if (pnl > 0) {
            balance -= pnl.toUint256();
        }

        require(
            _reservedAssets <= Math.mulDiv(balance, _maxUtilization, WAD * 1e12, Math.Rounding.Floor),
            POOL__MAX_UTILIZATION_EXCEEDED()
        );

        emit AssetsReserved(assets);
    }

    function releaseAssets(uint256 assets) external {
        require(msg.sender == _perpex, POOL__ONLY_PERPEX());
        require(assets <= _reservedAssets, POOL__INVALID_RELEASE_AMOUNT());

        _reservedAssets -= assets;

        emit AssetsReleased(assets);
    }

    function totalAssets() public view override returns (uint256) {
        int256 balance = ERC20(asset()).balanceOf(address(this)).toInt256() * 1e12;
        int256 pnl = IPerpex(_perpex).pnl();

        if (pnl > balance) {
            return 0;
        }

        return (balance - pnl).toUint256() / 1e12;
    }

    function availableAssets() public view returns (uint256) {
        uint256 balance = ERC20(asset()).balanceOf(address(this));
        if (_reservedAssets == 0) {
            return balance;
        }

        uint256 freeAssets = Math.min(balance - _reservedAssets, totalAssets());
        uint256 minRequiredAssets = Math.mulDiv(_reservedAssets, WAD, _maxUtilization, Math.Rounding.Ceil);

        if (freeAssets <= minRequiredAssets) {
            return 0;
        }

        return freeAssets - minRequiredAssets;
    }
}

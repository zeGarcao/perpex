// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IPool} from "./interfaces/IPool.sol";
import {IPerpex} from "./interfaces/IPerpex.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract Pool is IPool, ERC4626 {
    address private _perpex;

    constructor(address asset_) ERC4626(IERC20(asset_)) ERC20("Perpex Pool Token", "PPT") {}

    function totalAssets() public view override returns (uint256) {
        int256 balance = SafeCast.toInt256(super.totalAssets());
        int256 pnl = IPerpex(_perpex).pnl();

        if (pnl > balance) {
            return 0;
        }

        return SafeCast.toUint256(balance - pnl);
    }
}

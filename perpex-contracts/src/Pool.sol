// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IPool} from "./interfaces/IPool.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Pool is IPool, ERC4626 {
    constructor(address asset_) ERC4626(IERC20(asset_)) ERC20("Perpex Pool Token", "PPT") {}
}

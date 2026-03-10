// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IPool} from "./interfaces/IPool.sol";
import {IPerpex} from "./interfaces/IPerpex.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title Pool
/// @notice ERC4626 vault that backs Perpex positions with USDC liquidity
/// @dev Tracks reserved assets and enforces a utilization cap for protocol safety
contract Pool is IPool, ERC4626, AccessControl {
    using SafeCast for uint256;
    using SafeCast for int256;

    //////////////////////////////////////////////////////////////
    //                        CONSTANTS                         //
    //////////////////////////////////////////////////////////////

    /// @notice Hard cap for max utilization (85%, 18 decimals)
    uint256 private constant MAX_UTILIZATION = 0.85e18;

    /// @notice Role identifier for admin operations keccak256("ADMIN")
    bytes32 private constant ADMIN_ROLE = 0xdf8b4c520ffe197c5343c6f5aec59570151ef9a492f2c624fd45ddde6135ec42;

    /// @notice Role identifier for Perpex-only operations keccak256("PERPEX")
    bytes32 private constant PERPEX_ROLE = 0xeaa91350ea4f7485d1528814ef9ab69999281decb3e768abbcc35926ee435cbb;

    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    /// @notice Address of the Perpex core contract
    address public perpex;

    /// @notice Total assets currently reserved for open positions (6 decimals)
    uint256 private _reservedAssets;

    /// @notice Max allowed utilization ratio (18 decimals)
    uint256 private _maxUtilization;

    //////////////////////////////////////////////////////////////
    //                       CONSTRUCTOR                        //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Initializes the pool vault and role permissions
     * @param asset_ Address of the vault underlying asset (USDC)
     * @param maxUtilization Initial max utilization ratio (18 decimals)
     */
    constructor(address asset_, uint256 maxUtilization) ERC4626(IERC20(asset_)) ERC20("Perpex Pool Token", "PPT") {
        require(maxUtilization <= MAX_UTILIZATION, POOL__INVALID_MAX_UTILIZATION());

        _maxUtilization = maxUtilization;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    //////////////////////////////////////////////////////////////
    //                     ADMIN FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Updates the Perpex contract address
     * @param perpex_ New Perpex contract address
     */
    function setPerpex(address perpex_) external onlyRole(ADMIN_ROLE) {
        require(perpex_ != address(0), POOL__ZERO_ADDRESS());

        _revokeRole(PERPEX_ROLE, perpex);
        _grantRole(PERPEX_ROLE, perpex_);

        perpex = perpex_;

        emit PerpexUpdated(perpex_);
    }

    /**
     * @notice Updates the max utilization ratio
     * @param maxUtilization New max utilization ratio (18 decimals)
     */
    function setMaxUtilization(uint256 maxUtilization) external onlyRole(ADMIN_ROLE) {
        require(maxUtilization <= MAX_UTILIZATION, POOL__INVALID_MAX_UTILIZATION());

        _maxUtilization = maxUtilization;

        emit MaxUtilizationUpdated(maxUtilization);
    }

    //////////////////////////////////////////////////////////////
    //                  LIQUIDITY MANAGEMENT                    //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc IPool
    function reserveAssets(uint256 assets) external onlyRole(PERPEX_ROLE) {
        require(assets != 0, POOL__INVALID_RESERVE_AMOUNT());

        _reservedAssets += assets;

        uint256 balance = ERC20(asset()).balanceOf(address(this));
        int256 pnl = IPerpex(perpex).totalPnL();

        if (pnl > 0) {
            uint256 pnlScaled = FixedPointMathLib.divUp(pnl.toUint256(), 1e12);

            balance = pnlScaled >= balance ? 0 : balance - pnlScaled;
        }

        require(_reservedAssets <= FixedPointMathLib.mulWad(balance, _maxUtilization), POOL__MAX_UTILIZATION_EXCEEDED());

        emit AssetsReserved(assets);
    }

    /// @inheritdoc IPool
    function releaseAssets(uint256 assets) external onlyRole(PERPEX_ROLE) {
        require(assets != 0 && assets <= _reservedAssets, POOL__INVALID_RELEASE_AMOUNT());

        _reservedAssets -= assets;

        emit AssetsReleased(assets);
    }

    //////////////////////////////////////////////////////////////
    //                      VIEW FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc IPool
    function availableAssets() public view returns (uint256) {
        uint256 balance = ERC20(asset()).balanceOf(address(this));
        if (_reservedAssets == 0) {
            return balance;
        }

        uint256 freeAssets = FixedPointMathLib.min(balance - _reservedAssets, totalAssets());
        uint256 minRequiredAssets = FixedPointMathLib.divWadUp(_reservedAssets, _maxUtilization);

        if (freeAssets <= minRequiredAssets) {
            return 0;
        }

        return freeAssets - minRequiredAssets;
    }

    /// @inheritdoc ERC4626
    function totalAssets() public view override returns (uint256) {
        int256 balance = ERC20(asset()).balanceOf(address(this)).toInt256() * 1e12;
        int256 pnl = IPerpex(perpex).totalPnL();

        if (pnl > balance) {
            return 0;
        }

        return (balance - pnl).toUint256() / 1e12;
    }

    /// @inheritdoc ERC4626
    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 availableAssets_ = availableAssets();
        if (availableAssets_ == 0) {
            return 0;
        }

        uint256 availableShares = _convertToShares(availableAssets_, Math.Rounding.Floor);
        uint256 ownerBalance = balanceOf(owner);

        return FixedPointMathLib.min(availableShares, ownerBalance);
    }

    //////////////////////////////////////////////////////////////
    //                   INTERNAL FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ERC4626
    function _decimalsOffset() internal pure override returns (uint8) {
        return 12;
    }
}

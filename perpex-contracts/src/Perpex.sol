// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IPerpex} from "./interfaces/IPerpex.sol";
import {IPool} from "./interfaces/IPool.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {IChronicleOracle} from "./interfaces/IChronicleOracle.sol";

contract Perpex is IPerpex {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;
    using EnumerableSet for EnumerableSet.AddressSet;

    address private _usdc;
    address private _pool;
    uint256 private _nonce;
    uint256 private _minLeverage;
    uint256 private _maxLeverage;
    uint256 private _positionFee;
    uint256 private _liquidationThreshold;

    mapping(address token => address oracle) private _oracles;
    mapping(bytes32 id => Position position) private _positions;
    mapping(address token => mapping(PositionSide side => OpenInterest openInterest)) private _openInterests;

    EnumerableSet.AddressSet private _allowedTokens;

    constructor() {}

    function openPosition(address token, uint256 collateral, uint256 size, PositionSide side)
        external
        returns (bytes32 id)
    {
        require(_allowedTokens.contains(token), PERPEX__TOKEN_NOT_ALLOWED());

        uint256 usdcPriceInUsd = IChronicleOracle(_oracles[_usdc]).read();
        uint256 positionFee = _computePositionFee(size, usdcPriceInUsd);
        require(positionFee != 0, PERPEX__INVALID_POSITION_SIZE());
        require(collateral > positionFee, PERPEX__INSUFFICIENT_COLLATERAL());

        uint256 netCollateral = collateral - positionFee;
        uint256 leverage = _computeLeverage(size, netCollateral, usdcPriceInUsd);
        require(leverage >= _minLeverage && leverage <= _maxLeverage, PERPEX__LEVERAGE_OUT_OF_BOUNDS());

        uint256 tokenPriceInUsd = IChronicleOracle(_oracles[token]).read();
        uint256 sizeInTokens = _computeSizeInTokens(size, tokenPriceInUsd, ERC20(token).decimals(), side);

        Position memory position = Position({
            owner: msg.sender,
            token: token,
            collateral: netCollateral,
            size: size,
            sizeInTokens: sizeInTokens,
            side: side,
            isOpen: true
        });

        id = keccak256(abi.encode(msg.sender, position, block.chainid, ++_nonce));
        _positions[id] = position;

        _openInterests[token][side].value += size;
        _openInterests[token][side].tokens += sizeInTokens;

        emit PositionOpened(id, msg.sender);

        IPool(_pool).reserveAssets(FixedPointMathLib.mulDivUp(size, 1e6, usdcPriceInUsd));
        IERC20(_usdc).safeTransferFrom(msg.sender, _pool, positionFee);
        IERC20(_usdc).safeTransferFrom(msg.sender, address(this), netCollateral);
    }

    function increasePositionSize(bytes32 id, uint256 newSize) external {
        Position storage position = _positions[id];
        require(msg.sender == position.owner, PERPEX__NOT_POSITION_OWNER());
        require(position.isOpen, PERPEX__POSITION_ALREADY_CLOSED());
        require(newSize > position.size, PERPEX__INVALID_POSITION_SIZE());

        uint256 sizeDelta = newSize - position.size;

        uint256 usdcPriceInUsd = IChronicleOracle(_oracles[_usdc]).read();
        uint256 positionFee = _computePositionFee(sizeDelta, usdcPriceInUsd);
        require(positionFee != 0, PERPEX__INVALID_POSITION_SIZE());
        require(position.collateral > positionFee, PERPEX__INSUFFICIENT_COLLATERAL());

        uint256 netCollateral = position.collateral - positionFee;
        uint256 leverage = _computeLeverage(newSize, netCollateral, usdcPriceInUsd);
        require(leverage >= _minLeverage && leverage <= _maxLeverage, PERPEX__LEVERAGE_OUT_OF_BOUNDS());

        address positionToken = position.token;
        uint256 tokenPriceInUsd = IChronicleOracle(_oracles[positionToken]).read();
        uint256 sizeInTokens =
            _computeSizeInTokens(sizeDelta, tokenPriceInUsd, ERC20(positionToken).decimals(), position.side);

        position.size = newSize;
        position.collateral = netCollateral;
        position.sizeInTokens += sizeInTokens;

        _openInterests[positionToken][position.side].value += sizeDelta;
        _openInterests[positionToken][position.side].tokens += sizeInTokens;

        require(!_isPositionLiquidatable(position, usdcPriceInUsd, tokenPriceInUsd), PERPEX__LIQUIDATABLE_POSITION());

        emit PositionSizeIncreased(id, sizeDelta);

        IPool(_pool).reserveAssets(FixedPointMathLib.mulDivUp(sizeDelta, 1e6, usdcPriceInUsd));
        IERC20(_usdc).safeTransfer(_pool, positionFee);
    }

    function increasePositionCollateral(bytes32 id, uint256 collateral) external {
        Position storage position = _positions[id];
        require(msg.sender == position.owner, PERPEX__NOT_POSITION_OWNER());
        require(position.isOpen, PERPEX__POSITION_ALREADY_CLOSED());

        position.collateral += collateral;

        emit PositionCollateralIncreased(id, collateral);

        IERC20(_usdc).safeTransferFrom(msg.sender, address(this), collateral);
    }

    function totalPnL() external view returns (int256 pnl) {
        for (uint256 i = 0; i < _allowedTokens.length(); ++i) {
            address token = _allowedTokens.at(i);
            uint256 tokenPriceInUsd = IChronicleOracle(_oracles[token]).read();

            OpenInterest memory longOI = _openInterests[token][PositionSide.LONG];
            OpenInterest memory shortOI = _openInterests[token][PositionSide.SHORT];

            uint256 longAppreciation =
                FixedPointMathLib.mulWad(longOI.tokens * (10 ** (18 - ERC20(token).decimals())), tokenPriceInUsd);
            int256 longPnL = longAppreciation.toInt256() - longOI.value.toInt256();

            uint256 shortAppreciation =
                FixedPointMathLib.mulWadUp(shortOI.tokens * (10 ** (18 - ERC20(token).decimals())), tokenPriceInUsd);
            int256 shortPnL = shortOI.value.toInt256() - shortAppreciation.toInt256();

            pnl += longPnL + shortPnL;
        }
    }

    function positionPnL(bytes32 id) external view returns (int256 pnl) {
        Position memory position = _positions[id];
        require(position.owner != address(0), PERPEX__POSITION_NOT_FOUND());

        uint256 tokenPriceInUsd = IChronicleOracle(_oracles[position.token]).read();
        return _computePositionPnL(position, tokenPriceInUsd);
    }

    function isPositionLiquidatable(bytes32 id) external view returns (bool) {
        Position memory position = _positions[id];
        require(position.owner != address(0), PERPEX__POSITION_NOT_FOUND());

        uint256 usdcPriceInUsd = IChronicleOracle(_oracles[_usdc]).read();
        uint256 tokenPriceInUsd = IChronicleOracle(_oracles[position.token]).read();

        return _isPositionLiquidatable(position, usdcPriceInUsd, tokenPriceInUsd);
    }

    function totalOpenInterest() external view returns (uint256 oi) {
        for (uint256 i = 0; i < _allowedTokens.length(); ++i) {
            address token = _allowedTokens.at(i);
            oi += _openInterests[token][PositionSide.LONG].value;
            oi += _openInterests[token][PositionSide.SHORT].value;
        }
    }

    function _computeSizeInTokens(uint256 size, uint256 tokenPriceInUsd, uint8 tokenDecimals, PositionSide side)
        internal
        pure
        returns (uint256 sizeInTokens)
    {
        if (side == PositionSide.LONG) {
            sizeInTokens = FixedPointMathLib.divWad(size, tokenPriceInUsd * (10 ** (18 - tokenDecimals)));
        } else {
            sizeInTokens = FixedPointMathLib.divWadUp(size, tokenPriceInUsd * (10 ** (18 - tokenDecimals)));
        }
    }

    function _computePositionFee(uint256 size, uint256 usdcPriceInUsd) internal view returns (uint256 positionFee) {
        uint256 positionFeeInUsd = FixedPointMathLib.mulWadUp(size, _positionFee);
        positionFee = FixedPointMathLib.mulDivUp(positionFeeInUsd, 1e6, usdcPriceInUsd);
    }

    function _computeLeverage(uint256 size, uint256 collateral, uint256 usdcPriceInUsd)
        internal
        pure
        returns (uint256 leverage)
    {
        uint256 collateralInUsd = FixedPointMathLib.mulDiv(collateral, usdcPriceInUsd, 1e6);
        leverage = FixedPointMathLib.divWadUp(size, collateralInUsd);
    }

    function _computePositionPnL(Position memory position, uint256 tokenPriceInUsd) internal view returns (int256 pnl) {
        if (position.side == PositionSide.LONG) {
            uint256 appreciation = FixedPointMathLib.mulWad(
                position.sizeInTokens * (10 ** (18 - ERC20(position.token).decimals())), tokenPriceInUsd
            );
            pnl = appreciation.toInt256() - position.size.toInt256();
        } else {
            uint256 appreciation = FixedPointMathLib.mulWadUp(
                position.sizeInTokens * (10 ** (18 - ERC20(position.token).decimals())), tokenPriceInUsd
            );
            pnl = position.size.toInt256() - appreciation.toInt256();
        }
    }

    function _isPositionLiquidatable(Position memory position, uint256 usdcPriceInUsd, uint256 tokenPriceInUsd)
        internal
        view
        returns (bool)
    {
        int256 pnl = _computePositionPnL(position, tokenPriceInUsd);

        if (pnl >= 0) {
            return false;
        }

        uint256 loss = FixedPointMathLib.abs(pnl);
        uint256 collateralInUsd = FixedPointMathLib.mulDiv(position.collateral, usdcPriceInUsd, 1e6);
        uint256 maxLossAllowed = FixedPointMathLib.mulWad(collateralInUsd, _liquidationThreshold);

        return loss > maxLossAllowed;
    }
}

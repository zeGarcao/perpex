// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IPerpex} from "./interfaces/IPerpex.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IChronicleOracle} from "./interfaces/IChronicleOracle.sol";

contract Perpex is IPerpex {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant WAD = 1e18;

    address private _usdc;
    address private _pool;
    uint256 private _nonce;
    uint256 private _maxLeverage;
    uint256 private _positionFee;

    mapping(address token => address oracle) private _oracles;
    mapping(bytes32 id => Position position) private _positions;
    mapping(address token => mapping(PositionSide side => OpenInterest openInterest)) private _openInterests;

    EnumerableSet.AddressSet private _allowedTokens;

    constructor() {}

    function openPosition(address token, uint256 collateral, uint256 size, PositionSide side)
        external
        returns (bytes32 id)
    {
        // TODO: ensure enough liquidity in the pool for desired size

        require(_allowedTokens.contains(token), "token not allowed");

        uint256 positionFee = Math.mulDiv(size, _positionFee, WAD * 1e12, Math.Rounding.Ceil);
        require(positionFee != 0, "invalid position fee");
        require(collateral > positionFee, "collateral must be greater than position fee");

        uint256 netCollateral = collateral - positionFee;
        require(size >= netCollateral * 1e12, "invalid size");

        uint256 usdcPriceInUsd = IChronicleOracle(_oracles[_usdc]).read();
        uint256 collateralInUsd = Math.mulDiv(netCollateral * 1e12, usdcPriceInUsd, WAD, Math.Rounding.Floor);
        uint256 leverage = Math.mulDiv(size, WAD, collateralInUsd, Math.Rounding.Ceil);
        require(leverage <= _maxLeverage, "max leverage exceeded");

        uint256 tokenPriceInUsd = IChronicleOracle(_oracles[token]).read();
        uint256 sizeInTokens;
        if (side == PositionSide.LONG) {
            sizeInTokens =
                Math.mulDiv(size, WAD, tokenPriceInUsd * (10 ** (18 - ERC20(token).decimals())), Math.Rounding.Floor);
        } else {
            sizeInTokens =
                Math.mulDiv(size, WAD, tokenPriceInUsd * (10 ** (18 - ERC20(token).decimals())), Math.Rounding.Ceil);
        }

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

        emit PositionOpened(id, msg.sender);

        IERC20(_usdc).safeTransferFrom(msg.sender, _pool, positionFee);
        IERC20(_usdc).safeTransferFrom(msg.sender, address(this), netCollateral);
    }

    function pnl() external view returns (int256 pnl_) {
        for (uint256 i = 0; i < _allowedTokens.length(); ++i) {
            address token = _allowedTokens.at(i);
            uint256 tokenPriceInUsd = IChronicleOracle(_oracles[token]).read();

            OpenInterest memory longOI = _openInterests[token][PositionSide.LONG];
            OpenInterest memory shortOI = _openInterests[token][PositionSide.SHORT];

            uint256 longAppreciation = Math.mulDiv(
                longOI.tokens * (10 ** (18 - ERC20(token).decimals())), tokenPriceInUsd, WAD, Math.Rounding.Floor
            );
            int256 longPnL = longAppreciation.toInt256() - longOI.value.toInt256();

            uint256 shortAppreciation = Math.mulDiv(
                shortOI.tokens * (10 ** (18 - ERC20(token).decimals())), tokenPriceInUsd, WAD, Math.Rounding.Ceil
            );
            int256 shortPnL = shortOI.value.toInt256() - shortAppreciation.toInt256();

            pnl_ += longPnL + shortPnL;
        }
    }
}

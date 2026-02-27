// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IPerpex} from "./interfaces/IPerpex.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {IChronicleOracle} from "./interfaces/IChronicleOracle.sol";

contract Perpex is IPerpex {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    address private _usdc;
    address private _pool;
    uint256 private _nonce;
    uint256 private _maxLeverage;
    uint256 private _positionFee;

    mapping(address token => address oracle) private _oracles;
    mapping(bytes32 id => Position position) public positions;

    EnumerableSet.AddressSet private _allowedTokens;

    constructor() {}

    function openPosition(address token, uint256 collateral, uint256 size, PositionSide side)
        external
        returns (bytes32 id)
    {
        // TODO: ensure enough liquidity in the pool for desired size

        require(_allowedTokens.contains(token), "token not allowed");

        uint256 positionFee = FixedPointMathLib.mulWadUp(size, _positionFee);
        require(positionFee != 0, "invalid position fee");
        require(collateral > positionFee, "collateral must be greater than position fee");

        uint256 netCollateral = collateral - positionFee;
        require(size >= netCollateral, "invalid size");
        require(FixedPointMathLib.divWadUp(size, netCollateral) <= _maxLeverage, "max leverage exceeded");

        uint256 usdcPriceInUsd = IChronicleOracle(_oracles[_usdc]).read();
        uint256 tokenPriceInUsd = IChronicleOracle(_oracles[token]).read();
        uint256 tokenPriceInUsdc = FixedPointMathLib.divWadUp(tokenPriceInUsd, usdcPriceInUsd);
        uint256 sizeInTokens = FixedPointMathLib.divWad(size, tokenPriceInUsdc);

        Position memory position = Position({
            owner: msg.sender,
            token: token,
            collateral: netCollateral,
            size: size,
            sizeInTokens: sizeInTokens,
            side: side
        });

        id = keccak256(abi.encode(msg.sender, position, block.chainid, ++_nonce));
        positions[id] = position;

        emit PositionOpened(id, msg.sender);

        IERC20(_usdc).safeTransferFrom(msg.sender, _pool, positionFee);
        IERC20(_usdc).safeTransferFrom(msg.sender, address(this), netCollateral);
    }
}

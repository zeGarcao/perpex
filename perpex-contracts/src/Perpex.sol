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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Perpex
/// @notice Main contract for the Perpex perpetual exchange protocol
/// @dev Implements leveraged trading with USDC collateral and Chronicle oracle price feeds
contract Perpex is IPerpex, Ownable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;
    using EnumerableSet for EnumerableSet.AddressSet;

    //////////////////////////////////////////////////////////////
    //                        CONSTANTS                         //
    //////////////////////////////////////////////////////////////

    /// @notice Maximum allowed liquidation threshold (85%)
    uint256 private constant MAX_LIQUIDATION_THRESHOLD = 0.85e18;

    //////////////////////////////////////////////////////////////
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    /// @notice Address of the USDC token contract
    address private _usdc;

    /// @notice Address of the liquidity pool contract
    address private _pool;

    /// @notice Nonce for generating unique position IDs
    uint256 private _nonce;

    /// @notice Minimum allowed leverage (18 decimals)
    uint256 private _minLeverage;

    /// @notice Maximum allowed leverage (18 decimals)
    uint256 private _maxLeverage;

    /// @notice Fee charged for position management (18 decimals)
    uint256 private _positionFee;

    /// @notice Threshold at which positions become liquidatable (18 decimals)
    uint256 private _liquidationThreshold;

    /// @notice Mapping of token addresses to their Chronicle oracle addresses
    mapping(address token => address oracle) private _oracles;

    /// @notice Mapping of position IDs to position data
    mapping(bytes32 id => Position position) private _positions;

    /// @notice Mapping of tokens and sides to open interest data
    mapping(address token => mapping(PositionSide side => OpenInterest openInterest)) private _openInterests;

    /// @notice Set of tokens allowed for trading
    EnumerableSet.AddressSet private _allowedTokens;

    //////////////////////////////////////////////////////////////
    //                       CONSTRUCTOR                        //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Initializes the Perpex contract with configuration parameters
     * @param usdc Address of the USDC token contract
     * @param usdcOracle Address of the USDC Chronicle oracle
     * @param pool Address of the liquidity pool contract
     * @param minLeverage Minimum allowed leverage (18 decimals)
     * @param maxLeverage Maximum allowed leverage (18 decimals)
     * @param positionFee Fee for position management (18 decimals)
     * @param liquidationThreshold Threshold for position liquidation (18 decimals)
     * @param allowedTokens Array of token addresses allowed for trading
     * @param oracles Array of Chronicle oracle addresses for the allowed tokens
     */
    constructor(
        address usdc,
        address usdcOracle,
        address pool,
        uint256 minLeverage,
        uint256 maxLeverage,
        uint256 positionFee,
        uint256 liquidationThreshold,
        address[] memory allowedTokens,
        address[] memory oracles
    ) Ownable(msg.sender) {
        require(usdc != address(0), PERPEX__ZERO_ADDRESS());
        require(usdcOracle != address(0), PERPEX__ZERO_ADDRESS());
        require(pool != address(0), PERPEX__ZERO_ADDRESS());
        require(minLeverage != 0, PERPEX__INVALID_MIN_LEVERAGE());
        require(maxLeverage > minLeverage, PERPEX__INVALID_MAX_LEVERAGE());
        require(liquidationThreshold <= MAX_LIQUIDATION_THRESHOLD, PERPEX__INVALID_LIQUIDATION_THRESHOLD());

        _usdc = usdc;
        _oracles[usdc] = usdcOracle;
        _pool = pool;
        _minLeverage = minLeverage;
        _maxLeverage = maxLeverage;
        _positionFee = positionFee;
        _liquidationThreshold = liquidationThreshold;

        address token;
        address oracle;
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            token = allowedTokens[i];
            oracle = oracles[i];
            require(token != address(0), PERPEX__ZERO_ADDRESS());
            require(oracle != address(0), PERPEX__ZERO_ADDRESS());
            require(_allowedTokens.add(token), PERPEX__INVALID_TOKEN());

            _oracles[token] = oracle;
        }
    }

    //////////////////////////////////////////////////////////////
    //                     ADMIN FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Updates the minimum leverage requirement
     * @param minLeverage New minimum leverage value (18 decimals)
     */
    function setMinLeverage(uint256 minLeverage) external onlyOwner {
        require(minLeverage != 0 && minLeverage < _maxLeverage, PERPEX__INVALID_MIN_LEVERAGE());

        _minLeverage = minLeverage;

        emit MinLeverageUpdated(minLeverage);
    }

    /**
     * @notice Updates the maximum leverage allowed
     * @param maxLeverage New maximum leverage value (18 decimals)
     */
    function setMaxLeverage(uint256 maxLeverage) external onlyOwner {
        require(maxLeverage > _minLeverage, PERPEX__INVALID_MAX_LEVERAGE());

        _maxLeverage = maxLeverage;

        emit MaxLeverageUpdated(maxLeverage);
    }

    /**
     * @notice Updates the liquidation threshold
     * @param liquidationThreshold New liquidation threshold (18 decimals, max 80%)
     */
    function setLiquidationThreshold(uint256 liquidationThreshold) external onlyOwner {
        require(liquidationThreshold <= MAX_LIQUIDATION_THRESHOLD, PERPEX__INVALID_LIQUIDATION_THRESHOLD());

        _liquidationThreshold = liquidationThreshold;

        emit LiquidationThresholdUpdated(liquidationThreshold);
    }

    /**
     * @notice Updates the position fee
     * @param positionFee New position fee (18 decimals)
     */
    function setPositionFee(uint256 positionFee) external onlyOwner {
        _positionFee = positionFee;

        emit PositionFeeUpdated(positionFee);
    }

    /**
     * @notice Adds a new token to the list of allowed trading tokens
     * @param token Address of the token to add
     * @param oracle Address of the Chronicle oracle for the token
     */
    function addToken(address token, address oracle) external onlyOwner {
        require(token != address(0), PERPEX__ZERO_ADDRESS());
        require(oracle != address(0), PERPEX__ZERO_ADDRESS());
        require(_allowedTokens.add(token), PERPEX__INVALID_TOKEN());

        _oracles[token] = oracle;

        emit TokenAdded(token, oracle);
    }

    /**
     * @notice Removes a token from the list of allowed trading tokens
     * @param token Address of the token to remove
     */
    function removeToken(address token) external onlyOwner {
        require(_allowedTokens.remove(token), PERPEX__INVALID_TOKEN());

        delete _oracles[token];

        emit TokenRemoved(token);
    }

    //////////////////////////////////////////////////////////////
    //                   POSITION MANAGEMENT                    //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc IPerpex
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

    /// @inheritdoc IPerpex
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

    /// @inheritdoc IPerpex
    function increasePositionCollateral(bytes32 id, uint256 collateral) external {
        Position storage position = _positions[id];
        require(msg.sender == position.owner, PERPEX__NOT_POSITION_OWNER());
        require(position.isOpen, PERPEX__POSITION_ALREADY_CLOSED());

        position.collateral += collateral;

        emit PositionCollateralIncreased(id, collateral);

        IERC20(_usdc).safeTransferFrom(msg.sender, address(this), collateral);
    }

    //////////////////////////////////////////////////////////////
    //                      VIEW FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc IPerpex
    function totalPnL() external view returns (int256 pnl) {
        for (uint256 i = 0; i < _allowedTokens.length(); ++i) {
            address token = _allowedTokens.at(i);
            uint256 tokenPriceInUsd = IChronicleOracle(_oracles[token]).read();

            OpenInterest memory longOi = _openInterests[token][PositionSide.LONG];
            OpenInterest memory shortOi = _openInterests[token][PositionSide.SHORT];

            uint256 longAppreciation =
                FixedPointMathLib.mulWad(longOi.tokens * (10 ** (18 - ERC20(token).decimals())), tokenPriceInUsd);
            int256 longPnL = longAppreciation.toInt256() - longOi.value.toInt256();

            uint256 shortAppreciation =
                FixedPointMathLib.mulWadUp(shortOi.tokens * (10 ** (18 - ERC20(token).decimals())), tokenPriceInUsd);
            int256 shortPnL = shortOi.value.toInt256() - shortAppreciation.toInt256();

            pnl += longPnL + shortPnL;
        }
    }

    /// @inheritdoc IPerpex
    function positionPnL(bytes32 id) external view returns (int256 pnl) {
        Position memory position = _positions[id];
        require(position.owner != address(0), PERPEX__POSITION_NOT_FOUND());

        uint256 tokenPriceInUsd = IChronicleOracle(_oracles[position.token]).read();
        return _computePositionPnL(position, tokenPriceInUsd);
    }

    /// @inheritdoc IPerpex
    function isPositionLiquidatable(bytes32 id) external view returns (bool) {
        Position memory position = _positions[id];
        require(position.owner != address(0), PERPEX__POSITION_NOT_FOUND());

        uint256 usdcPriceInUsd = IChronicleOracle(_oracles[_usdc]).read();
        uint256 tokenPriceInUsd = IChronicleOracle(_oracles[position.token]).read();

        return _isPositionLiquidatable(position, usdcPriceInUsd, tokenPriceInUsd);
    }

    /// @inheritdoc IPerpex
    function totalOpenInterest() external view returns (uint256 oi) {
        for (uint256 i = 0; i < _allowedTokens.length(); ++i) {
            address token = _allowedTokens.at(i);
            oi += _openInterests[token][PositionSide.LONG].value;
            oi += _openInterests[token][PositionSide.SHORT].value;
        }
    }

    //////////////////////////////////////////////////////////////
    //                   INTERNAL FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Converts position size from USD value to token amount
     * @param size Position size in USD value (18 decimals)
     * @param tokenPriceInUsd Token price from Chronicle oracle (18 decimals)
     * @param tokenDecimals Token's decimal precision
     * @param side Position side (affects rounding direction)
     * @return sizeInTokens Position size in token's native decimals
     */
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

    /**
     * @notice Calculates the position fee in USDC
     * @param size Position size in USD value (18 decimals)
     * @param usdcPriceInUsd USDC price from Chronicle oracle (18 decimals)
     * @return positionFee Fee amount in USDC (6 decimals)
     */
    function _computePositionFee(uint256 size, uint256 usdcPriceInUsd) internal view returns (uint256 positionFee) {
        uint256 positionFeeInUsd = FixedPointMathLib.mulWadUp(size, _positionFee);
        positionFee = FixedPointMathLib.mulDivUp(positionFeeInUsd, 1e6, usdcPriceInUsd);
    }

    /**
     * @notice Calculates the leverage of a position
     * @param size Position size in USD value (18 decimals)
     * @param collateral Collateral amount in USDC (6 decimals)
     * @param usdcPriceInUsd USDC price from Chronicle oracle (18 decimals)
     * @return leverage Position leverage (18 decimals)
     */
    function _computeLeverage(uint256 size, uint256 collateral, uint256 usdcPriceInUsd)
        internal
        pure
        returns (uint256 leverage)
    {
        uint256 collateralInUsd = FixedPointMathLib.mulDiv(collateral, usdcPriceInUsd, 1e6);
        leverage = FixedPointMathLib.divWadUp(size, collateralInUsd);
    }

    /**
     * @notice Calculates the profit or loss for a position
     * @param position The position data
     * @param tokenPriceInUsd Current token price from Chronicle oracle (18 decimals)
     * @return pnl Position PnL in USD value (18 decimals), can be negative
     */
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

    /**
     * @notice Checks if a position exceeds the liquidation threshold
     * @param position The position data
     * @param usdcPriceInUsd USDC price from Chronicle oracle (18 decimals)
     * @param tokenPriceInUsd Token price from Chronicle oracle (18 decimals)
     * @return True if position losses exceed liquidation threshold, false otherwise
     */
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

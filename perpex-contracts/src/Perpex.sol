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
    //                     STATE VARIABLES                      //
    //////////////////////////////////////////////////////////////

    /// @notice Address of the USDC token contract
    address private _usdc;

    /// @notice Address of the liquidity pool contract
    address public pool;

    /// @notice Nonce for generating unique position IDs
    uint256 private _nonce;

    /// @notice Maintenance margin requirement (18 decimals)
    uint256 public maintenanceMargin;

    /// @notice Fee charged for position management (18 decimals)
    uint256 public positionFee;

    /// @notice Mapping of token addresses to their Chronicle oracle addresses
    mapping(address token => address oracle) public oracles;

    /// @notice Mapping of position IDs to position data
    mapping(bytes32 id => Position position) public positions;

    /// @notice Mapping of tokens and sides to open interest data
    mapping(address token => mapping(PositionSide side => OpenInterest openInterest)) public openInterests;

    /// @notice Set of tokens allowed for trading
    EnumerableSet.AddressSet private _allowedTokens;

    //////////////////////////////////////////////////////////////
    //                       CONSTRUCTOR                        //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Initializes the Perpex contract with configuration parameters
     * @param usdc Address of the USDC token contract
     * @param usdcOracle Address of the USDC Chronicle oracle
     * @param pool_ Address of the liquidity pool contract
     * @param maintenanceMargin_ Maintenance margin requirement (18 decimals)
     * @param positionFee_ Fee for position management (18 decimals)
     * @param allowedTokens_ Array of token addresses allowed for trading
     * @param oracles_ Array of Chronicle oracle addresses for the allowed tokens
     */
    constructor(
        address usdc,
        address usdcOracle,
        address pool_,
        uint256 maintenanceMargin_,
        uint256 positionFee_,
        address[] memory allowedTokens_,
        address[] memory oracles_
    ) Ownable(msg.sender) {
        require(usdc != address(0), PERPEX__ZERO_ADDRESS());
        require(usdcOracle != address(0), PERPEX__ZERO_ADDRESS());
        require(pool_ != address(0), PERPEX__ZERO_ADDRESS());
        require(maintenanceMargin_ != 0, PERPEX__INVALID_MAINTENANCE_MARGIN());

        _usdc = usdc;
        oracles[usdc] = usdcOracle;
        pool = pool_;
        maintenanceMargin = maintenanceMargin_;
        positionFee = positionFee_;

        address token;
        address oracle;
        for (uint256 i = 0; i < allowedTokens_.length; i++) {
            token = allowedTokens_[i];
            oracle = oracles_[i];
            require(token != address(0), PERPEX__ZERO_ADDRESS());
            require(oracle != address(0), PERPEX__ZERO_ADDRESS());
            require(_allowedTokens.add(token), PERPEX__INVALID_TOKEN());

            oracles[token] = oracle;
        }
    }

    //////////////////////////////////////////////////////////////
    //                     ADMIN FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Updates the pool contract address
     * @param pool_ New pool address
     */
    function setPool(address pool_) external onlyOwner {
        require(pool_ != address(0), PERPEX__ZERO_ADDRESS());

        pool = pool_;

        emit PoolUpdated(pool_);
    }

    function setMaintenanceMargin(uint256 maintenanceMargin_) external onlyOwner {
        require(maintenanceMargin_ != 0, PERPEX__INVALID_MAINTENANCE_MARGIN());

        maintenanceMargin = maintenanceMargin_;

        emit MaintenanceMarginUpdated(maintenanceMargin_);
    }

    /**
     * @notice Updates the position fee
     * @param positionFee_ New position fee (18 decimals)
     */
    function setPositionFee(uint256 positionFee_) external onlyOwner {
        require(positionFee_ != 0, PERPEX__INVALID_POSITION_FEE());

        positionFee = positionFee_;

        emit PositionFeeUpdated(positionFee_);
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

        oracles[token] = oracle;

        emit TokenAdded(token, oracle);
    }

    /**
     * @notice Removes a token from the list of allowed trading tokens
     * @param token Address of the token to remove
     */
    function removeToken(address token) external onlyOwner {
        require(_allowedTokens.remove(token), PERPEX__INVALID_TOKEN());

        delete oracles[token];

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
        require(_isAllowedToken(token), PERPEX__TOKEN_NOT_ALLOWED());

        uint256 usdcPriceInUsd = IChronicleOracle(oracles[_usdc]).read();
        uint256 positionFee_ = _computePositionFee(size, usdcPriceInUsd);
        require(collateral > positionFee_, PERPEX__INSUFFICIENT_COLLATERAL());

        uint256 netCollateral = collateral - positionFee_;
        uint256 tokenPriceInUsd = IChronicleOracle(oracles[token]).read();
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

        require(!_isPositionLiquidatable(position, usdcPriceInUsd, tokenPriceInUsd), PERPEX__LIQUIDATABLE_POSITION());

        id = keccak256(abi.encode(msg.sender, position, block.chainid, ++_nonce));
        positions[id] = position;

        openInterests[token][side].value += size;
        openInterests[token][side].tokens += sizeInTokens;

        emit PositionOpened(id, msg.sender);

        IPool(pool).reserveAssets(FixedPointMathLib.mulDivUp(size, 1e6, usdcPriceInUsd));
        IERC20(_usdc).safeTransferFrom(msg.sender, pool, positionFee_);
        IERC20(_usdc).safeTransferFrom(msg.sender, address(this), netCollateral);
    }

    /// @inheritdoc IPerpex
    function increasePositionSize(bytes32 id, uint256 newSize) external {
        Position storage position = positions[id];
        require(msg.sender == position.owner, PERPEX__NOT_POSITION_OWNER());
        require(position.isOpen, PERPEX__POSITION_ALREADY_CLOSED());
        require(newSize > position.size, PERPEX__INVALID_POSITION_SIZE());

        uint256 sizeDelta = newSize - position.size;

        uint256 usdcPriceInUsd = IChronicleOracle(oracles[_usdc]).read();
        uint256 positionFee_ = _computePositionFee(sizeDelta, usdcPriceInUsd);
        require(position.collateral >= positionFee_, PERPEX__INSUFFICIENT_COLLATERAL());

        address positionToken = position.token;
        uint256 tokenPriceInUsd = IChronicleOracle(oracles[positionToken]).read();
        uint256 sizeInTokens =
            _computeSizeInTokens(sizeDelta, tokenPriceInUsd, ERC20(positionToken).decimals(), position.side);

        position.size = newSize;
        position.collateral -= positionFee_;
        position.sizeInTokens += sizeInTokens;

        openInterests[positionToken][position.side].value += sizeDelta;
        openInterests[positionToken][position.side].tokens += sizeInTokens;

        require(!_isPositionLiquidatable(position, usdcPriceInUsd, tokenPriceInUsd), PERPEX__LIQUIDATABLE_POSITION());

        emit PositionSizeIncreased(id, sizeDelta);

        IPool(pool).reserveAssets(FixedPointMathLib.mulDivUp(sizeDelta, 1e6, usdcPriceInUsd));
        IERC20(_usdc).safeTransfer(pool, positionFee_);
    }

    /// @inheritdoc IPerpex
    function increasePositionCollateral(bytes32 id, uint256 collateral) external {
        Position storage position = positions[id];
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
            uint256 tokenPriceInUsd = IChronicleOracle(oracles[token]).read();

            OpenInterest memory longOi = openInterests[token][PositionSide.LONG];
            OpenInterest memory shortOi = openInterests[token][PositionSide.SHORT];

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
        Position memory position = positions[id];
        require(position.owner != address(0), PERPEX__POSITION_NOT_FOUND());

        uint256 tokenPriceInUsd = IChronicleOracle(oracles[position.token]).read();
        return _computePositionPnL(position, tokenPriceInUsd);
    }

    /// @inheritdoc IPerpex
    function isPositionLiquidatable(bytes32 id) external view returns (bool) {
        Position memory position = positions[id];
        require(position.owner != address(0), PERPEX__POSITION_NOT_FOUND());

        uint256 usdcPriceInUsd = IChronicleOracle(oracles[_usdc]).read();
        uint256 tokenPriceInUsd = IChronicleOracle(oracles[position.token]).read();

        return _isPositionLiquidatable(position, usdcPriceInUsd, tokenPriceInUsd);
    }

    /// @inheritdoc IPerpex
    function totalOpenInterest() external view returns (uint256 oi) {
        for (uint256 i = 0; i < _allowedTokens.length(); ++i) {
            address token = _allowedTokens.at(i);
            oi += openInterests[token][PositionSide.LONG].value;
            oi += openInterests[token][PositionSide.SHORT].value;
        }
    }

    /// @inheritdoc IPerpex
    function isAllowedToken(address token) public view returns (bool) {
        return _isAllowedToken(token);
    }

    /// @inheritdoc IPerpex
    function maxLeverage() external view returns (uint256) {
        return FixedPointMathLib.divWad(1e18, maintenanceMargin);
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
    function _computePositionFee(uint256 size, uint256 usdcPriceInUsd) internal view returns (uint256) {
        uint256 positionFeeInUsd = FixedPointMathLib.mulWadUp(size, positionFee);
        return FixedPointMathLib.mulDivUp(positionFeeInUsd, 1e6, usdcPriceInUsd);
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
        uint256 collateralInUsd = FixedPointMathLib.mulDiv(position.collateral, usdcPriceInUsd, 1e6);
        int256 totalValue = collateralInUsd.toInt256() + _computePositionPnL(position, tokenPriceInUsd);
        uint256 maintenanceMarginInUsd = FixedPointMathLib.mulWad(position.size, maintenanceMargin);

        return totalValue < maintenanceMarginInUsd.toInt256();
    }

    /**
     * @notice Checks if a token is in the allowed tokens set
     * @param token The address of the token to check
     * @return True if the token is allowed, false otherwise
     */
    function _isAllowedToken(address token) internal view returns (bool) {
        return _allowedTokens.contains(token);
    }
}

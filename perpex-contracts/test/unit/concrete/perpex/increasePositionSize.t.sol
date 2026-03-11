// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Perpex_Unit_Shared_Test} from "../../shared/Perpex.t.sol";
import {IPerpex} from "../../../../src/interfaces/IPerpex.sol";

contract IncreasePositionSize_Unit_Concrete_Test is Perpex_Unit_Shared_Test {
    uint256 constant POOL_BALANCE = 100_000e6;
    uint256 constant USER_BALANCE = 100_000e6;

    uint256 constant INITIAL_POSITION_SIZE = 10_000e18;
    uint256 constant INITIAL_COLLATERAL = 1_000e6;
    uint256 constant EXPECTED_INITIAL_POSITION_FEE = 10e6;
    uint256 constant INITIAL_NET_COLLATERAL = 990e6;
    uint256 constant EXPECTED_SIZE_IN_TOKENS = 5e18;

    uint256 constant SIZE_DELTA = 5_000e18;
    uint256 constant NEW_SIZE = INITIAL_POSITION_SIZE + SIZE_DELTA;
    uint256 constant EXPECTED_FEE_FOR_DELTA = 5e6;
    uint256 constant EXPECTED_SIZE_IN_TOKENS_DELTA = 2.5e18;

    IPerpex.PositionSide constant SIDE = IPerpex.PositionSide.LONG;

    bytes32 positionId;
    uint256 newSize;
    address token;

    function setUp() public override {
        Perpex_Unit_Shared_Test.setUp();

        usdc.mint(address(pool), POOL_BALANCE);
        usdc.mint(bob, USER_BALANCE);

        vm.prank(bob);
        usdc.approve(address(perpex), type(uint256).max);

        // Create initial position
        vm.prank(bob);
        positionId = perpex.openPosition(address(weth), INITIAL_COLLATERAL, INITIAL_POSITION_SIZE, SIDE);

        token = address(weth);
    }

    //////////////////////////////////////////////////////////////
    //                     SETUP MODIFIERS                      //
    //////////////////////////////////////////////////////////////

    modifier whenCallerIsNotPositionOwner() {
        vm.prank(alice);
        _;
    }

    modifier whenCallerIsPositionOwner() {
        vm.prank(bob);
        _;
    }

    // TODO: implement this once the `closePosition` function is implemented
    modifier whenPositionIsAlreadyClosed() {
        _;
    }

    modifier whenPositionIsOpen() {
        _;
    }

    modifier whenNewSizeIsLessThanOrEqualToCurrentSize() {
        newSize = INITIAL_POSITION_SIZE;
        _;
    }

    modifier whenNewSizeIsGreaterThanCurrentSize() {
        newSize = NEW_SIZE;
        _;
    }

    modifier whenCollateralIsLessThanComputedPositionFeeForSizeDelta() {
        newSize = INITIAL_POSITION_SIZE + 995_000e18;
        _;
    }

    modifier whenCollateralIsGreaterThanOrEqualToComputedPositionFeeForSizeDelta() {
        newSize = NEW_SIZE;
        _;
    }

    modifier whenResultingPositionIsLiquidatable() {
        newSize = INITIAL_POSITION_SIZE + 50_000e18;
        _;
    }

    modifier whenResultingPositionIsNotLiquidatable() {
        newSize = NEW_SIZE;
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotPositionOwner() public whenCallerIsNotPositionOwner {
        vm.expectRevert(IPerpex.PERPEX__NOT_POSITION_OWNER.selector);

        perpex.increasePositionSize(positionId, newSize);
    }

    // TODO: Implement after closePosition is implemented
    function test_RevertWhen_PositionIsAlreadyClosed() public whenCallerIsPositionOwner whenPositionIsAlreadyClosed {
        vm.skip(true, "not implemented");
    }

    function test_RevertWhen_NewSizeIsLessThanOrEqualToCurrentSize()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenNewSizeIsLessThanOrEqualToCurrentSize
    {
        vm.expectRevert(IPerpex.PERPEX__INVALID_POSITION_SIZE.selector);

        perpex.increasePositionSize(positionId, newSize);
    }

    function test_RevertWhen_CollateralIsLessThanComputedPositionFeeForSizeDelta()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenNewSizeIsGreaterThanCurrentSize
        whenCollateralIsLessThanComputedPositionFeeForSizeDelta
    {
        vm.expectRevert(IPerpex.PERPEX__INSUFFICIENT_COLLATERAL.selector);

        perpex.increasePositionSize(positionId, newSize);
    }

    function test_RevertWhen_ResultingPositionIsLiquidatable()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenNewSizeIsGreaterThanCurrentSize
        whenCollateralIsGreaterThanOrEqualToComputedPositionFeeForSizeDelta
        whenResultingPositionIsLiquidatable
    {
        vm.expectRevert(IPerpex.PERPEX__LIQUIDATABLE_POSITION.selector);

        perpex.increasePositionSize(positionId, newSize);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_IncreasePositionSize_PositionSizeUpdated()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenNewSizeIsGreaterThanCurrentSize
        whenCollateralIsGreaterThanOrEqualToComputedPositionFeeForSizeDelta
        whenResultingPositionIsNotLiquidatable
    {
        perpex.increasePositionSize(positionId, newSize);

        (,,, uint256 posSize,,,) = perpex.positions(positionId);

        assertEq(posSize, newSize);
    }

    function test_IncreasePositionSize_PositionCollateralDecreased()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenNewSizeIsGreaterThanCurrentSize
        whenCollateralIsGreaterThanOrEqualToComputedPositionFeeForSizeDelta
        whenResultingPositionIsNotLiquidatable
    {
        perpex.increasePositionSize(positionId, newSize);

        (,, uint256 posCollateral,,,,) = perpex.positions(positionId);

        assertEq(posCollateral, INITIAL_NET_COLLATERAL - EXPECTED_FEE_FOR_DELTA);
    }

    function test_IncreasePositionSize_PositionSizeInTokensIncreased()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenNewSizeIsGreaterThanCurrentSize
        whenCollateralIsGreaterThanOrEqualToComputedPositionFeeForSizeDelta
        whenResultingPositionIsNotLiquidatable
    {
        perpex.increasePositionSize(positionId, newSize);

        (,,,, uint256 posSizeInTokens,,) = perpex.positions(positionId);

        assertEq(posSizeInTokens, EXPECTED_SIZE_IN_TOKENS + EXPECTED_SIZE_IN_TOKENS_DELTA);
    }

    function test_IncreasePositionSize_OpenInterestIncreased()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenNewSizeIsGreaterThanCurrentSize
        whenCollateralIsGreaterThanOrEqualToComputedPositionFeeForSizeDelta
        whenResultingPositionIsNotLiquidatable
    {
        perpex.increasePositionSize(positionId, newSize);

        (uint256 value, uint256 tokens) = perpex.openInterests(token, SIDE);

        assertEq(value, INITIAL_POSITION_SIZE + SIZE_DELTA);
        assertEq(tokens, EXPECTED_SIZE_IN_TOKENS + EXPECTED_SIZE_IN_TOKENS_DELTA);
        assertEq(perpex.totalOpenInterest(), INITIAL_POSITION_SIZE + SIZE_DELTA);
    }

    function test_IncreasePositionSize_EventEmitted()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenNewSizeIsGreaterThanCurrentSize
        whenCollateralIsGreaterThanOrEqualToComputedPositionFeeForSizeDelta
        whenResultingPositionIsNotLiquidatable
    {
        vm.expectEmit(true, true, false, false, address(perpex));
        emit IPerpex.PositionSizeIncreased(positionId, SIZE_DELTA);

        perpex.increasePositionSize(positionId, newSize);
    }

    function test_IncreasePositionSize_ReserveAssetsCalledOnPoolWithExpectedAmount()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenNewSizeIsGreaterThanCurrentSize
        whenCollateralIsGreaterThanOrEqualToComputedPositionFeeForSizeDelta
        whenResultingPositionIsNotLiquidatable
    {
        uint256 expectedReservedAssets = 5_000e6; // SIZE_DELTA / usdcPrice

        vm.expectCall(address(pool), abi.encodeWithSelector(pool.reserveAssets.selector, expectedReservedAssets));

        perpex.increasePositionSize(positionId, newSize);
    }

    function test_IncreasePositionSize_PositionFeeTransferredToPool()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenNewSizeIsGreaterThanCurrentSize
        whenCollateralIsGreaterThanOrEqualToComputedPositionFeeForSizeDelta
        whenResultingPositionIsNotLiquidatable
    {
        vm.expectCall(
            address(usdc), abi.encodeWithSelector(usdc.transfer.selector, address(pool), EXPECTED_FEE_FOR_DELTA)
        );

        perpex.increasePositionSize(positionId, newSize);
    }
}

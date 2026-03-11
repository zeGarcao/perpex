// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Perpex_Unit_Shared_Test} from "../../shared/Perpex.t.sol";
import {IPerpex} from "../../../../src/interfaces/IPerpex.sol";

contract OpenPosition_Unit_Concrete_Test is Perpex_Unit_Shared_Test {
    uint256 constant POOL_BALANCE = 100_000e6;
    uint256 constant USER_BALANCE = 100_000e6;

    uint256 constant VALID_SIZE = 10_000e18;
    uint256 constant VALID_COLLATERAL = 1_000e6;

    uint256 constant EXPECTED_POSITION_FEE = 10e6;
    uint256 constant EXPECTED_NET_COLLATERAL = 990e6;
    uint256 constant EXPECTED_RESERVED_ASSETS = 10_000e6;
    uint256 constant EXPECTED_SIZE_IN_TOKENS = 5e18;

    IPerpex.PositionSide constant SIDE = IPerpex.PositionSide.LONG;

    address token;
    uint256 collateral;
    uint256 size;

    function setUp() public override {
        Perpex_Unit_Shared_Test.setUp();

        usdc.mint(address(pool), POOL_BALANCE);
        usdc.mint(bob, USER_BALANCE);

        vm.prank(bob);
        usdc.approve(address(perpex), type(uint256).max);
    }

    //////////////////////////////////////////////////////////////
    //                     SETUP MODIFIERS                      //
    //////////////////////////////////////////////////////////////

    modifier whenTokenIsNotAllowed() {
        token = address(link);
        _;
    }

    modifier whenTokenIsAllowed() {
        token = address(weth);
        _;
    }

    modifier whenCollateralIsLessThanOrEqualToComputedPositionFee() {
        size = VALID_SIZE;
        collateral = EXPECTED_POSITION_FEE;
        _;
    }

    modifier whenCollateralIsGreaterThanComputedPositionFee() {
        collateral = VALID_COLLATERAL;
        _;
    }

    modifier whenResultingPositionIsLiquidatable() {
        size = 25_000e18;
        _;
    }

    modifier whenResultingPositionIsNotLiquidatable() {
        size = VALID_SIZE;
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_TokenIsNotAllowed() public whenTokenIsNotAllowed {
        vm.prank(bob);
        vm.expectRevert(IPerpex.PERPEX__TOKEN_NOT_ALLOWED.selector);

        perpex.openPosition(token, collateral, size, SIDE);
    }

    function test_RevertWhen_CollateralIsLessThanOrEqualToComputedPositionFee()
        public
        whenTokenIsAllowed
        whenCollateralIsLessThanOrEqualToComputedPositionFee
    {
        vm.prank(bob);
        vm.expectRevert(IPerpex.PERPEX__INSUFFICIENT_COLLATERAL.selector);

        perpex.openPosition(token, collateral, size, SIDE);
    }

    function test_RevertWhen_ResultingPositionIsLiquidatable()
        public
        whenTokenIsAllowed
        whenCollateralIsGreaterThanComputedPositionFee
        whenResultingPositionIsLiquidatable
    {
        vm.prank(bob);
        vm.expectRevert(IPerpex.PERPEX__LIQUIDATABLE_POSITION.selector);

        perpex.openPosition(token, collateral, size, SIDE);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_OpenPosition_PositionCreatedWithExpectedValues()
        public
        whenTokenIsAllowed
        whenCollateralIsGreaterThanComputedPositionFee
        whenResultingPositionIsNotLiquidatable
    {
        vm.prank(bob);
        bytes32 id = perpex.openPosition(token, collateral, size, SIDE);

        (
            address posOwner,
            address posToken,
            uint256 posCollateral,
            uint256 posSize,
            uint256 posSizeInTokens,
            IPerpex.PositionSide posSide,
            bool posIsOpen
        ) = perpex.positions(id);

        assertEq(posOwner, bob);
        assertEq(posToken, token);
        assertEq(posCollateral, EXPECTED_NET_COLLATERAL);
        assertEq(posSize, size);
        assertEq(posSizeInTokens, EXPECTED_SIZE_IN_TOKENS);
        assertEq(uint8(posSide), uint8(SIDE));
        assertTrue(posIsOpen);
    }

    function test_OpenPosition_TotalOpenInterestIncreasedForTokenAndSide()
        public
        whenTokenIsAllowed
        whenCollateralIsGreaterThanComputedPositionFee
        whenResultingPositionIsNotLiquidatable
    {
        vm.prank(bob);
        perpex.openPosition(token, collateral, size, SIDE);

        (uint256 value, uint256 tokens) = perpex.openInterests(token, SIDE);

        assertEq(value, size);
        assertEq(tokens, EXPECTED_SIZE_IN_TOKENS);
        assertEq(perpex.totalOpenInterest(), size);
    }

    function test_OpenPosition_EventEmitted()
        public
        whenTokenIsAllowed
        whenCollateralIsGreaterThanComputedPositionFee
        whenResultingPositionIsNotLiquidatable
    {
        bytes32 expectedPosId = keccak256(
            abi.encode(
                bob,
                IPerpex.Position({
                    owner: bob,
                    token: token,
                    collateral: EXPECTED_NET_COLLATERAL,
                    size: size,
                    sizeInTokens: EXPECTED_SIZE_IN_TOKENS,
                    side: SIDE,
                    isOpen: true
                }),
                block.chainid,
                1
            )
        );

        vm.expectEmit(true, true, false, false, address(perpex));
        emit IPerpex.PositionOpened(expectedPosId, bob);

        vm.prank(bob);
        perpex.openPosition(token, collateral, size, SIDE);
    }

    function test_OpenPosition_ReserveAssetsCalledOnPoolWithExpectedAssetsAmount()
        public
        whenTokenIsAllowed
        whenCollateralIsGreaterThanComputedPositionFee
        whenResultingPositionIsNotLiquidatable
    {
        vm.expectCall(address(pool), abi.encodeWithSelector(pool.reserveAssets.selector, EXPECTED_RESERVED_ASSETS));

        vm.prank(bob);
        perpex.openPosition(token, collateral, size, SIDE);
    }

    function test_OpenPosition_PositionFeeTransferredFromUserToPool()
        public
        whenTokenIsAllowed
        whenCollateralIsGreaterThanComputedPositionFee
        whenResultingPositionIsNotLiquidatable
    {
        vm.expectCall(
            address(usdc), abi.encodeWithSelector(usdc.transferFrom.selector, bob, address(pool), EXPECTED_POSITION_FEE)
        );

        vm.prank(bob);
        perpex.openPosition(token, collateral, size, SIDE);
    }

    function test_OpenPosition_NetCollateralTransferredFromUserToPerpex()
        public
        whenTokenIsAllowed
        whenCollateralIsGreaterThanComputedPositionFee
        whenResultingPositionIsNotLiquidatable
    {
        uint256 perpexBalanceBefore = usdc.balanceOf(address(perpex));

        vm.prank(bob);
        perpex.openPosition(token, collateral, size, SIDE);

        assertEq(usdc.balanceOf(address(perpex)), perpexBalanceBefore + EXPECTED_NET_COLLATERAL);
    }
}

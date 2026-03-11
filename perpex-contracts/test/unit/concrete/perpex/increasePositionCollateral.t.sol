// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Perpex_Unit_Shared_Test} from "../../shared/Perpex.t.sol";
import {IPerpex} from "../../../../src/interfaces/IPerpex.sol";

contract IncreasePositionCollateral_Unit_Concrete_Test is Perpex_Unit_Shared_Test {
    uint256 constant POOL_BALANCE = 100_000e6;
    uint256 constant USER_BALANCE = 100_000e6;

    uint256 constant INITIAL_POSITION_SIZE = 10_000e18;
    uint256 constant INITIAL_COLLATERAL = 1_000e6;
    uint256 constant INITIAL_NET_COLLATERAL = 990e6;
    uint256 constant COLLATERAL_DELTA = 100e6;

    IPerpex.PositionSide constant SIDE = IPerpex.PositionSide.LONG;

    bytes32 positionId;
    uint256 collateral;

    function setUp() public override {
        Perpex_Unit_Shared_Test.setUp();

        usdc.mint(address(pool), POOL_BALANCE);
        usdc.mint(bob, USER_BALANCE);

        vm.prank(bob);
        usdc.approve(address(perpex), type(uint256).max);

        vm.prank(bob);
        positionId = perpex.openPosition(address(weth), INITIAL_COLLATERAL, INITIAL_POSITION_SIZE, SIDE);
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

    modifier whenCollateralAmountIsValid() {
        collateral = COLLATERAL_DELTA;
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotPositionOwner() public whenCallerIsNotPositionOwner {
        vm.expectRevert(IPerpex.PERPEX__NOT_POSITION_OWNER.selector);

        perpex.increasePositionCollateral(positionId, collateral);
    }

    // TODO: Implement after closePosition is implemented
    function test_RevertWhen_PositionIsAlreadyClosed() public whenCallerIsPositionOwner whenPositionIsAlreadyClosed {
        vm.skip(true, "not implemented");
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_IncreasePositionCollateral_PositionCollateralIncreased()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenCollateralAmountIsValid
    {
        perpex.increasePositionCollateral(positionId, collateral);

        (,, uint256 posCollateral,,,,) = perpex.positions(positionId);

        assertEq(posCollateral, INITIAL_NET_COLLATERAL + collateral);
    }

    function test_IncreasePositionCollateral_EventEmitted()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenCollateralAmountIsValid
    {
        vm.expectEmit(true, false, false, true, address(perpex));
        emit IPerpex.PositionCollateralIncreased(positionId, collateral);

        perpex.increasePositionCollateral(positionId, collateral);
    }

    function test_IncreasePositionCollateral_CollateralTransferredFromUserToPerpex()
        public
        whenCallerIsPositionOwner
        whenPositionIsOpen
        whenCollateralAmountIsValid
    {
        perpex.increasePositionCollateral(positionId, collateral);

        assertEq(usdc.balanceOf(address(perpex)), INITIAL_NET_COLLATERAL + collateral);
    }
}

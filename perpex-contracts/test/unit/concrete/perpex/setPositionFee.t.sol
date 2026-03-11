// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Perpex_Unit_Shared_Test} from "../../shared/Perpex.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPerpex} from "../../../../src/interfaces/IPerpex.sol";

contract SetPositionFee_Unit_Concrete_Test is Perpex_Unit_Shared_Test {
    uint256 newPositionFee;

    function setUp() public override {
        Perpex_Unit_Shared_Test.setUp();
    }

    //////////////////////////////////////////////////////////////
    //                     SETUP MODIFIERS                      //
    //////////////////////////////////////////////////////////////

    modifier whenCallerIsNotOwner() {
        vm.prank(bob);
        _;
    }

    modifier whenCallerIsOwner() {
        vm.prank(owner);
        _;
    }

    modifier whenPositionFeeIsZero() {
        newPositionFee = 0;
        _;
    }

    modifier whenPositionFeeIsNotZero() {
        newPositionFee = 0.005e18;
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotOwner() public whenCallerIsNotOwner {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));

        perpex.setPositionFee(newPositionFee);
    }

    function test_RevertWhen_PositionFeeIsZero() public whenCallerIsOwner whenPositionFeeIsZero {
        vm.expectRevert(IPerpex.PERPEX__INVALID_POSITION_FEE.selector);

        perpex.setPositionFee(newPositionFee);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_SetPositionFee_ValueUpdated() public whenCallerIsOwner whenPositionFeeIsNotZero {
        perpex.setPositionFee(newPositionFee);

        assertEq(perpex.positionFee(), newPositionFee);
    }

    function test_SetPositionFee_EventEmitted() public whenCallerIsOwner whenPositionFeeIsNotZero {
        vm.expectEmit(false, false, false, true, address(perpex));
        emit IPerpex.PositionFeeUpdated(newPositionFee);

        perpex.setPositionFee(newPositionFee);
    }
}

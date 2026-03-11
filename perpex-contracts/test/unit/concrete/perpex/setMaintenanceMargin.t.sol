// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Perpex_Unit_Shared_Test} from "../../shared/Perpex.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPerpex} from "../../../../src/interfaces/IPerpex.sol";

contract SetMaintenanceMargin_Unit_Concrete_Test is Perpex_Unit_Shared_Test {
    uint256 newMaintenanceMargin;

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

    modifier whenIsZero() {
        newMaintenanceMargin = 0;
        _;
    }

    modifier whenIsNotZero() {
        newMaintenanceMargin = 0.2e18;
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotOwner() public whenCallerIsNotOwner {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));

        perpex.setMaintenanceMargin(newMaintenanceMargin);
    }

    function test_RevertWhen_Zero() public whenCallerIsOwner whenIsZero {
        vm.expectRevert(IPerpex.PERPEX__INVALID_MAINTENANCE_MARGIN.selector);

        perpex.setMaintenanceMargin(newMaintenanceMargin);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_SetMaintenanceMargin_ValueUpdated() public whenCallerIsOwner whenIsNotZero {
        perpex.setMaintenanceMargin(newMaintenanceMargin);

        assertEq(perpex.maintenanceMargin(), newMaintenanceMargin);
    }

    function test_SetMaintenanceMargin_EventEmitted() public whenCallerIsOwner whenIsNotZero {
        vm.expectEmit(false, false, false, true, address(perpex));
        emit IPerpex.MaintenanceMarginUpdated(newMaintenanceMargin);

        perpex.setMaintenanceMargin(newMaintenanceMargin);
    }
}

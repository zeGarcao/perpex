// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Pool_Unit_Shared_Test} from "../../shared/Pool.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IPool} from "../../../../src/interfaces/IPool.sol";

contract SetMaxUtilization_Unit_Concrete_Test is Pool_Unit_Shared_Test {
    uint256 newMaxUtilization;

    function setUp() public override {
        Pool_Unit_Shared_Test.setUp();
    }

    //////////////////////////////////////////////////////////////
    //                     SETUP MODIFIERS                      //
    //////////////////////////////////////////////////////////////

    modifier whenCallerIsNotAdmin() {
        vm.prank(bob);
        _;
    }

    modifier whenCallerIsAdmin() {
        vm.prank(owner);
        _;
    }

    modifier whenExceedsMaxUtilization() {
        newMaxUtilization = 0.9e18;
        _;
    }

    modifier whenDoesNotExceedMaxUtilization() {
        newMaxUtilization = 0.75e18;
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotAdmin() public whenCallerIsNotAdmin {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, ADMIN_ROLE)
        );

        pool.setMaxUtilization(newMaxUtilization);
    }

    function test_RevertWhen_ExceedsMaxUtilization() public whenCallerIsAdmin whenExceedsMaxUtilization {
        vm.expectRevert(IPool.POOL__INVALID_MAX_UTILIZATION.selector);

        pool.setMaxUtilization(newMaxUtilization);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_SetMaxUtilization_ValueUpdated() public whenCallerIsAdmin whenDoesNotExceedMaxUtilization {
        pool.setMaxUtilization(newMaxUtilization);

        assertEq(pool.maxUtilization(), newMaxUtilization);
    }

    function test_SetMaxUtilization_EventEmitted() public whenCallerIsAdmin whenDoesNotExceedMaxUtilization {
        vm.expectEmit(false, false, false, true, address(pool));
        emit IPool.MaxUtilizationUpdated(newMaxUtilization);

        pool.setMaxUtilization(newMaxUtilization);
    }
}

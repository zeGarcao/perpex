// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Pool_Unit_Shared_Test} from "../../shared/Pool.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IPool} from "../../../../src/interfaces/IPool.sol";

contract SetPerpex_Unit_Concrete_Test is Pool_Unit_Shared_Test {
    address newPerpex;

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

    modifier whenIsZeroAddress() {
        newPerpex = address(0);
        _;
    }

    modifier whenIsNotZeroAddress() {
        newPerpex = address(0x123);
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotAdmin() public whenCallerIsNotAdmin {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, ADMIN_ROLE)
        );

        pool.setPerpex(newPerpex);
    }

    function test_RevertWhen_ZeroAddress() public whenCallerIsAdmin whenIsZeroAddress {
        vm.expectRevert(IPool.POOL__ZERO_ADDRESS.selector);

        pool.setPerpex(newPerpex);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_SetPerpex_AddressUpdated() public whenCallerIsAdmin whenIsNotZeroAddress {
        pool.setPerpex(newPerpex);

        assertEq(pool.perpex(), newPerpex);
    }

    function test_SetPerpex_PerpexRoleRevokedFromOldAddress() public whenCallerIsAdmin whenIsNotZeroAddress {
        pool.setPerpex(newPerpex);

        assertEq(pool.hasRole(PERPEX_ROLE, address(perpex)), false);
    }

    function test_SetPerpex_PerpexRoleGrantedToNewAddress() public whenCallerIsAdmin whenIsNotZeroAddress {
        pool.setPerpex(newPerpex);

        assertEq(pool.hasRole(PERPEX_ROLE, address(newPerpex)), true);
    }

    function test_SetPerpex_EventEmitted() public whenCallerIsAdmin whenIsNotZeroAddress {
        vm.expectEmit(true, false, false, true, address(pool));
        emit IPool.PerpexUpdated(newPerpex);

        pool.setPerpex(newPerpex);
    }
}

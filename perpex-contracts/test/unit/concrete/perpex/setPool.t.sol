// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Perpex_Unit_Shared_Test} from "../../shared/Perpex.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPerpex} from "../../../../src/interfaces/IPerpex.sol";

contract SetPool_Unit_Concrete_Test is Perpex_Unit_Shared_Test {
    address newPool;

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

    modifier whenIsZeroAddress() {
        newPool = address(0);
        _;
    }

    modifier whenIsNotZeroAddress() {
        newPool = address(0x123);
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotOwner() public whenCallerIsNotOwner {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));

        perpex.setPool(newPool);
    }

    function test_RevertWhen_ZeroAddress() public whenCallerIsOwner whenIsZeroAddress {
        vm.expectRevert(IPerpex.PERPEX__ZERO_ADDRESS.selector);

        perpex.setPool(newPool);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_SetPool_PoolAddressUpdated() public whenCallerIsOwner whenIsNotZeroAddress {
        perpex.setPool(newPool);

        assertEq(perpex.pool(), newPool);
    }

    function test_SetPool_EventEmitted() public whenCallerIsOwner whenIsNotZeroAddress {
        vm.expectEmit(true, false, false, true, address(perpex));
        emit IPerpex.PoolUpdated(newPool);

        perpex.setPool(newPool);
    }
}

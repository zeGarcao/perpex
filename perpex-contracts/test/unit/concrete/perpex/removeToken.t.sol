// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Perpex_Unit_Shared_Test} from "../../shared/Perpex.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPerpex} from "../../../../src/interfaces/IPerpex.sol";

contract RemoveToken_Unit_Concrete_Test is Perpex_Unit_Shared_Test {
    address token;

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

    modifier whenTokenIsNotAllowed() {
        token = address(link);
        _;
    }

    modifier whenTokenIsAllowed() {
        token = address(weth);
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotOwner() public whenCallerIsNotOwner {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));

        perpex.removeToken(token);
    }

    function test_RevertWhen_TokenIsNotAllowed() public whenCallerIsOwner whenTokenIsNotAllowed {
        vm.expectRevert(IPerpex.PERPEX__INVALID_TOKEN.selector);

        perpex.removeToken(token);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_RemoveToken_AllowedTokenListUpdated() public whenCallerIsOwner whenTokenIsAllowed {
        perpex.removeToken(token);

        assertFalse(perpex.isAllowedToken(token));
    }

    function test_RemoveToken_OracleMappingUpdated() public whenCallerIsOwner whenTokenIsAllowed {
        perpex.removeToken(token);

        assertEq(perpex.oracles(token), address(0));
    }

    function test_RemoveToken_EventEmitted() public whenCallerIsOwner whenTokenIsAllowed {
        vm.expectEmit(true, false, false, true, address(perpex));
        emit IPerpex.TokenRemoved(token);

        perpex.removeToken(token);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Perpex_Unit_Shared_Test} from "../../shared/Perpex.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPerpex} from "../../../../src/interfaces/IPerpex.sol";

contract AddToken_Unit_Concrete_Test is Perpex_Unit_Shared_Test {
    address token;
    address oracle;

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

    modifier whenTokenIsZeroAddress() {
        token = address(0);
        oracle = address(0x123);
        _;
    }

    modifier whenOracleIsZeroAddress() {
        token = address(0x456);
        oracle = address(0);
        _;
    }

    modifier whenTokenIsAlreadyAllowed() {
        token = address(weth);
        oracle = address(wethOracle);
        _;
    }

    modifier whenTokenAndOracleAreValidAndTokenIsNotAllowedYet() {
        token = address(link);
        oracle = address(linkOracle);
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotOwner() public whenCallerIsNotOwner {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));

        perpex.addToken(token, oracle);
    }

    function test_RevertWhen_TokenIsZeroAddress() public whenCallerIsOwner whenTokenIsZeroAddress {
        vm.expectRevert(IPerpex.PERPEX__ZERO_ADDRESS.selector);

        perpex.addToken(token, oracle);
    }

    function test_RevertWhen_OracleIsZeroAddress() public whenCallerIsOwner whenOracleIsZeroAddress {
        vm.expectRevert(IPerpex.PERPEX__ZERO_ADDRESS.selector);

        perpex.addToken(token, oracle);
    }

    function test_RevertWhen_TokenIsAlreadyAllowed() public whenCallerIsOwner whenTokenIsAlreadyAllowed {
        vm.expectRevert(IPerpex.PERPEX__INVALID_TOKEN.selector);

        perpex.addToken(token, oracle);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_AddToken_AllowedTokenListUpdated()
        public
        whenCallerIsOwner
        whenTokenAndOracleAreValidAndTokenIsNotAllowedYet
    {
        perpex.addToken(token, oracle);

        assertTrue(perpex.isAllowedToken(token));
    }

    function test_AddToken_OracleMappingUpdated()
        public
        whenCallerIsOwner
        whenTokenAndOracleAreValidAndTokenIsNotAllowedYet
    {
        perpex.addToken(token, oracle);

        assertEq(perpex.oracles(token), oracle);
    }

    function test_AddToken_EventEmitted() public whenCallerIsOwner whenTokenAndOracleAreValidAndTokenIsNotAllowedYet {
        vm.expectEmit(true, false, false, true, address(perpex));
        emit IPerpex.TokenAdded(token, oracle);

        perpex.addToken(token, oracle);
    }
}

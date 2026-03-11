// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Pool_Unit_Shared_Test} from "../../shared/Pool.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IPool} from "../../../../src/interfaces/IPool.sol";

contract ReserveAssets_Unit_Concrete_Test is Pool_Unit_Shared_Test {
    // 1,000 USDC — pool liquidity seeded for each test
    uint256 constant POOL_BALANCE = 1000e6;

    // With INITIAL_MAX_UTILIZATION = 60%, max reserve = 600e6
    uint256 constant ASSETS_WITHIN_LIMIT = 500e6;
    uint256 constant ASSETS_EXCEEDING_LIMIT = 601e6;

    uint256 assets;

    function setUp() public override {
        Pool_Unit_Shared_Test.setUp();

        // Seed pool with USDC liquidity
        usdc.mint(address(pool), POOL_BALANCE);
    }

    //////////////////////////////////////////////////////////////
    //                     SETUP MODIFIERS                      //
    //////////////////////////////////////////////////////////////

    modifier whenCallerIsNotPerpex() {
        vm.prank(bob);
        _;
    }

    modifier whenCallerIsPerpex() {
        vm.prank(address(perpex));
        _;
    }

    modifier whenAssetsIsZero() {
        assets = 0;
        _;
    }

    modifier whenAssetsIsNotZero() {
        assets = ASSETS_WITHIN_LIMIT;
        _;
    }

    modifier whenExceedsMaxUtilization() {
        assets = ASSETS_EXCEEDING_LIMIT;
        _;
    }

    modifier whenDoesNotExceedMaxUtilization() {
        assets = ASSETS_WITHIN_LIMIT;
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotPerpex() public whenCallerIsNotPerpex {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, PERPEX_ROLE)
        );

        pool.reserveAssets(ASSETS_WITHIN_LIMIT);
    }

    function test_RevertWhen_AssetsIsZero() public whenCallerIsPerpex whenAssetsIsZero {
        vm.expectRevert(IPool.POOL__INVALID_RESERVE_AMOUNT.selector);

        pool.reserveAssets(assets);
    }

    function test_RevertWhen_ExceedsMaxUtilization() public whenCallerIsPerpex whenExceedsMaxUtilization {
        vm.expectRevert(IPool.POOL__MAX_UTILIZATION_EXCEEDED.selector);

        pool.reserveAssets(assets);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_ReserveAssets_ReservedAssetsIncreased() public whenCallerIsPerpex whenDoesNotExceedMaxUtilization {
        pool.reserveAssets(assets);

        assertEq(pool.reservedAssets(), assets);
    }

    function test_ReserveAssets_EventEmitted() public whenCallerIsPerpex whenDoesNotExceedMaxUtilization {
        vm.expectEmit(false, false, false, true, address(pool));
        emit IPool.AssetsReserved(assets);

        pool.reserveAssets(assets);
    }
}

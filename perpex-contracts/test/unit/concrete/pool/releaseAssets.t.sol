// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Pool_Unit_Shared_Test} from "../../shared/Pool.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IPool} from "../../../../src/interfaces/IPool.sol";

contract ReleaseAssets_Unit_Concrete_Test is Pool_Unit_Shared_Test {
    // 1,000 USDC — pool liquidity seeded for each test
    uint256 constant POOL_BALANCE = 1000e6;

    // With INITIAL_MAX_UTILIZATION = 60%, max reserve = 600e6
    uint256 constant RESERVED_AMOUNT = 500e6;

    uint256 assets;

    function setUp() public override {
        Pool_Unit_Shared_Test.setUp();

        // Seed pool with USDC liquidity
        usdc.mint(address(pool), POOL_BALANCE);

        // Pre-reserve assets so there is something to release
        vm.prank(address(perpex));
        pool.reserveAssets(RESERVED_AMOUNT);
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

    modifier whenAssetsExceedsReserved() {
        assets = RESERVED_AMOUNT + 1;
        _;
    }

    modifier whenAssetsIsValid() {
        assets = RESERVED_AMOUNT;
        _;
    }

    //////////////////////////////////////////////////////////////
    //                      UNHAPPY PATHS                       //
    //////////////////////////////////////////////////////////////

    function test_RevertWhen_CallerIsNotPerpex() public whenCallerIsNotPerpex {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, PERPEX_ROLE)
        );

        pool.releaseAssets(RESERVED_AMOUNT);
    }

    function test_RevertWhen_AssetsIsZero() public whenCallerIsPerpex whenAssetsIsZero {
        vm.expectRevert(IPool.POOL__INVALID_RELEASE_AMOUNT.selector);

        pool.releaseAssets(assets);
    }

    function test_RevertWhen_AssetsExceedsReserved() public whenCallerIsPerpex whenAssetsExceedsReserved {
        vm.expectRevert(IPool.POOL__INVALID_RELEASE_AMOUNT.selector);

        pool.releaseAssets(assets);
    }

    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    function test_ReleaseAssets_ReservedAssetsDecreased() public whenCallerIsPerpex whenAssetsIsValid {
        pool.releaseAssets(assets);

        assertEq(pool.reservedAssets(), 0);
    }

    function test_ReleaseAssets_EventEmitted() public whenCallerIsPerpex whenAssetsIsValid {
        vm.expectEmit(false, false, false, true, address(pool));
        emit IPool.AssetsReleased(assets);

        pool.releaseAssets(assets);
    }
}

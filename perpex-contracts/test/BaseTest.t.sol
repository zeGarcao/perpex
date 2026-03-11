// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Perpex} from "../src/Perpex.sol";
import {Pool} from "../src/Pool.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ChronicleOracleMock as OracleMock} from "./mocks/ChronicleOracleMock.sol";

abstract contract BaseTest is Test {
    // initial configuration values
    uint256 constant INITIAL_POSITION_FEE = 0.001e18; // 0.1%
    uint256 constant INITIAL_MAINTENANCE_MARGIN = 0.05e18; // 5%

    uint256 constant INITIAL_MAX_UTILIZATION = 0.6e18; // 60%
    bytes32 constant ADMIN_ROLE = 0xdf8b4c520ffe197c5343c6f5aec59570151ef9a492f2c624fd45ddde6135ec42;
    bytes32 constant PERPEX_ROLE = 0xeaa91350ea4f7485d1528814ef9ab69999281decb3e768abbcc35926ee435cbb;

    // core contracts
    Perpex perpex;
    Pool pool;

    // tokens
    ERC20Mock usdc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    ERC20Mock link;

    // oracle
    OracleMock usdcOracle;
    OracleMock wethOracle;
    OracleMock wbtcOracle;
    OracleMock linkOracle;

    // actors
    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address alice = makeAddr("alice");

    function setUp() public virtual {
        usdc = new ERC20Mock("USD Coin", "USDC", 6);
        weth = new ERC20Mock("Wrapped Ether", "WETH", 18);
        wbtc = new ERC20Mock("Wrapped Bitcoin", "WBTC", 8);
        link = new ERC20Mock("Chainlink", "LINK", 18);

        usdcOracle = new OracleMock(1e18); // $1.0
        wethOracle = new OracleMock(2000e18); // $2,000.0
        wbtcOracle = new OracleMock(70000e18); // $70,000.0
        linkOracle = new OracleMock(10e18); // $10.0

        vm.startPrank(owner);
        pool = new Pool(address(usdc), INITIAL_MAX_UTILIZATION);

        address[] memory allowedTokens = new address[](2);
        allowedTokens[0] = address(weth);
        allowedTokens[1] = address(wbtc);

        address[] memory oracles = new address[](2);
        oracles[0] = address(wethOracle);
        oracles[1] = address(wbtcOracle);

        perpex = new Perpex(
            address(usdc),
            address(usdcOracle),
            address(pool),
            INITIAL_MAINTENANCE_MARGIN,
            INITIAL_POSITION_FEE,
            allowedTokens,
            oracles
        );

        pool.setPerpex(address(perpex));
        vm.stopPrank();
    }
}

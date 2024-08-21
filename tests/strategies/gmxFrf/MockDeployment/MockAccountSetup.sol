// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {
    ChainlinkAggregatorMock
} from "../../../mocks/ChainlinkAggregatorMock.sol";
import { MockArbSys } from "../../../mocks/MockArbSys.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    UpgradeableBeacon
} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { GmxFrfStrategyMetadata } from "./GmxFrfStrategyMetadata.sol";
import {
    GmxFrfStrategyManager
} from "../../../../contracts/strategies/gmxFrf/GmxFrfStrategyManager.sol";
import {
    IGmxFrfStrategyManager
} from "../../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";
import {
    GmxFrfStrategyDeployer
} from "../../../../contracts/strategies/gmxFrf/GmxFrfStrategyDeployer.sol";
import {
    IStrategyBank
} from "../../../../contracts/interfaces/IStrategyBank.sol";
import {
    IInterestRateModel
} from "../../../../contracts/interfaces/IInterestRateModel.sol";
import {
    IStrategyReserve
} from "../../../../contracts/interfaces/IStrategyReserve.sol";
import {
    IDeploymentConfiguration
} from "../../../../contracts/strategies/gmxFrf/interfaces/IDeploymentConfiguration.sol";
import {
    IMarketConfiguration
} from "../../../../contracts/strategies/gmxFrf/interfaces/IMarketConfiguration.sol";
import {
    IChainlinkAdapter
} from "../../../../contracts/adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import {
    IChainlinkAggregatorV3
} from "../../../../contracts/adapters/chainlink/interfaces/external/IChainlinkAggregatorV3.sol";
import {
    MockChainlinkDataStreamVerifier
} from "./MockChainlinkDataStreamVerifier.sol";
import { MockAccountExtension } from "./MockAccountExtension.sol";
import {
    StrategyController
} from "../../../../contracts/core/StrategyController.sol";
import {
    UniswapSwapHandler
} from "@periphery/contracts/liquidation/UniswapSwapHandler.sol";
import {
    UniversalRouterSwapHandler
} from "@periphery/contracts/liquidation/UniversalRouterSwapHandler.sol";

abstract contract MockAccountSetup is Test, GmxFrfStrategyMetadata {
    UniswapSwapHandler SWAPHANDLER;
    UniversalRouterSwapHandler SWAPHANDLERV2;
    MockArbSys ARBSYS;

    ChainlinkAggregatorMock USDC_USD_ORACLE_MOCK;
    ChainlinkAggregatorMock ETH_USD_ORACLE_MOCK;
    ChainlinkAggregatorMock ARB_USD_ORACLE_MOCK;
    ChainlinkAggregatorMock BTC_USD_ORACLE_MOCK;
    ChainlinkAggregatorMock LINK_USD_ORACLE_MOCK;
    ChainlinkAggregatorMock GMX_USD_ORACLE_MOCK;

    GmxFrfStrategyManager MANAGER;
    GmxFrfStrategyDeployer DEPLOYER;
    StrategyController CONTROLLER;
    IStrategyBank BANK;
    IStrategyReserve RESERVE;
    MockAccountExtension ACCOUNT;

    constructor() {
        SWAPHANDLER = new UniswapSwapHandler(USDC);
        SWAPHANDLERV2 = new UniversalRouterSwapHandler(USDC, UNIVERSAL_ROUTER);

        // Etch the arbsys precompile, since Foundy's Arbitrum environment does not contain precompiles when simulating/forking.
        _etchArbSys();
        // Etch the mock Chainlink data stream verifier. This allows for spoofing of GMX order keepers.
        _etchMockChainlinkDataStreamVerifier();

        // Deploy the GMX Strategy. This includes
        // - Manager Proxy
        // - GmxFrfStrategyManager
        // - Beacon Factory
        // - GmxFrfStrategyAccount
        // - GmxFrfStrategyAccountDeployer
        _deployGmxFrfStrategy();

        // Deploy the core contracts, ensuring the Bank's AccountDeployer points to the `GmxFrfStrategyAccountDeployer` deployed in the previous step.
        // - Strategy Controller
        // - Strategy Reserve
        // - Strategy Bank
        _deployCore();

        // Approves markets for testing. For simplicity, uses the same configuration (unless modified for a specific test) as the live strategy.
        _approveMarkets();

        // Create a test account. The test account inherits from the deployed `GmxFrfStrategyAccount`, but contains an additional method that allows
        // the execution of arbitrary functions.
        _createAccount();

        // Takes funds from Binance's wallet to use to create artificial testing scenarios.
        _stealFunds();

        // Fund the reserve with USDC.
        _lendFunds(1e11);
        _addCollateral(1e10);
        _borrow(4e10);

        // Etch mock oracles to the addresses of the actual oracles. This allows for testing scenarios that would be invoked due to a change in asset price.
        // The mock oracles always default to the real value until changed.
        USDC_USD_ORACLE_MOCK = _etchMockOracle(USDC_USD_ORACLE);
        ETH_USD_ORACLE_MOCK = _etchMockOracle(ETH_USD_ORACLE);
        ARB_USD_ORACLE_MOCK = _etchMockOracle(ARB_USD_ORACLE);
        BTC_USD_ORACLE_MOCK = _etchMockOracle(BTC_USD_ORACLE);
        LINK_USD_ORACLE_MOCK = _etchMockOracle(LINK_USD_ORACLE);
        GMX_USD_ORACLE_MOCK = _etchMockOracle(GMX_USD_ORACLE);
    }

    function _etchArbSys() private {
        // Since foundry for some reason doesn't handle predeploys (even though they say they do);
        MockArbSys arbSys = new MockArbSys();
        vm.etch(
            address(0x0000000000000000000000000000000000000064),
            address(arbSys).code
        );
        ARBSYS = MockArbSys(
            address(0x0000000000000000000000000000000000000064)
        );
    }

    function _etchMockChainlinkDataStreamVerifier() private {
        MockChainlinkDataStreamVerifier verifier = new MockChainlinkDataStreamVerifier();
        vm.etch(
            address(0x478Aa2aC9F6D65F84e09D9185d126c3a17c2a93C),
            address(verifier).code
        );
    }

    function _deployGmxFrfStrategy() private {
        address managerLogic = address(
            new GmxFrfStrategyManager(USDC, WETH, address(this))
        );

        IDeploymentConfiguration.Deployments
            memory deployments = getDeployments();

        IMarketConfiguration.SharedOrderParameters
            memory sharedOrderParameters = IMarketConfiguration
                .SharedOrderParameters(
                    1000000,
                    100000000000000000,
                    bytes32(
                        0x676F6C646C696E6B000000000000000000000000000000000000000000000000
                    ),
                    0x62dF56DcEaaFEcBbb57D595E8Cf0b90cA437e77d,
                    1100000000000000000
                );

        IChainlinkAdapter.OracleConfiguration
            memory oracleConfiguration = IChainlinkAdapter.OracleConfiguration(
                100000,
                USDC_USD_ORACLE
            );

        bytes memory initializerData = abi.encodeWithSelector(
            GmxFrfStrategyManager.initialize.selector,
            deployments,
            sharedOrderParameters,
            oracleConfiguration,
            300
        );

        address managerProxy = address(
            new TransparentUpgradeableProxy(
                managerLogic,
                address(this), // initialOwner for the proxy admin
                initializerData
            )
        );

        MANAGER = GmxFrfStrategyManager(managerProxy);

        IGmxFrfStrategyManager manager = IGmxFrfStrategyManager(managerProxy);

        address accountLogic = address(new MockAccountExtension(manager));

        address accountBeacon = address(
            new UpgradeableBeacon(accountLogic, address(this))
        );

        DEPLOYER = new GmxFrfStrategyDeployer(accountBeacon);
    }

    function _deployCore() private {
        IStrategyBank.BankParameters memory bankParams = IStrategyBank
            .BankParameters(
                250000000000000000,
                166666666666666666,
                10000000000000000,
                50000000000000000,
                75000000000000000,
                10000000,
                DEPLOYER
            );

        IInterestRateModel.InterestRateModelParameters
            memory interestRateModel = IInterestRateModel
                .InterestRateModelParameters(
                    900000000000000000,
                    80000000000000000,
                    1055600000000000,
                    150000000000000000
                );

        IStrategyReserve.ReserveParameters
            memory reserveParams = IStrategyReserve.ReserveParameters(
                1000000000000,
                interestRateModel,
                "GoldLink GMX Funding Rate Farming Reserve Shares",
                "GFRF"
            );

        CONTROLLER = new StrategyController(
            address(this),
            USDC,
            reserveParams,
            bankParams
        );

        BANK = CONTROLLER.STRATEGY_BANK();
        RESERVE = CONTROLLER.STRATEGY_RESERVE();
    }

    function _approveMarkets() private {
        IChainlinkAdapter.OracleConfiguration
            memory oracleConfiguration = IChainlinkAdapter.OracleConfiguration(
                7200,
                ETH_USD_ORACLE
            );
        IMarketConfiguration.OrderPricingParameters
            memory orderPricingParameters = IMarketConfiguration
                .OrderPricingParameters(
                    30000000000000000,
                    30000000000000000,
                    2,
                    50000000000000000000000000000000000,
                    true
                );

        IMarketConfiguration.PositionParameters
            memory positionParameters = IMarketConfiguration.PositionParameters(
                10000000000000000000000000000000,
                75000000000000000000000000000000000
            );

        IMarketConfiguration.UnwindParameters
            memory unwindParameters = IMarketConfiguration.UnwindParameters(
                1050000000000000000,
                100000000000000,
                1200000000000000000,
                20000000000000000
            );

        MANAGER.setMarket(
            ETH_USD_MARKET,
            oracleConfiguration,
            orderPricingParameters,
            positionParameters,
            unwindParameters,
            30000000000000000
        );

        oracleConfiguration.oracle = ARB_USD_ORACLE;

        MANAGER.setMarket(
            ARB_USD_MARKET,
            oracleConfiguration,
            orderPricingParameters,
            positionParameters,
            unwindParameters,
            30000000000000000
        );

        oracleConfiguration.oracle = GMX_USD_ORACLE;

        MANAGER.setMarket(
            GMX_USD_MARKET,
            oracleConfiguration,
            orderPricingParameters,
            positionParameters,
            unwindParameters,
            30000000000000000
        );
    }

    function _stealFunds() internal {
        vm.deal(address(this), 20 ether);
        WETH.deposit{ value: 10 ether }();
        vm.prank(0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D);
        USDC.transfer(address(this), 1e12);
        vm.prank(0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D);
        ARB.transfer(address(this), 1e24);
        vm.prank(0x69eC552BE56E6505703f0C861c40039e5702037A);
        WBTC.transfer(address(this), 1e9);
        vm.prank(0x25431341A5800759268a6aC1d3CD91C029D7d9CA);
        LINK.transfer(address(this), 1000e18);
        vm.prank(0x5a52E96BAcdaBb82fd05763E25335261B270Efcb);
        GMX.transfer(address(this), 10000e18);
    }

    function _createAccount() internal {
        ACCOUNT = MockAccountExtension(
            payable(BANK.executeOpenAccount(address(this)))
        );
    }

    function _lendFunds(uint256 amount) internal {
        USDC.approve(address(RESERVE), amount);
        RESERVE.deposit(amount, address(this));
    }

    function _addCollateral(uint256 amount) internal {
        USDC.approve(address(BANK), amount);
        ACCOUNT.executeAddCollateral(amount);
    }

    function _borrow(uint256 amount) internal {
        ACCOUNT.executeBorrow(amount);
    }

    function _etchMockOracle(
        IChainlinkAggregatorV3 toMock
    ) internal returns (ChainlinkAggregatorMock mocked) {
        // Get the decimals and currentAnswer of the real oracle. Later,
        // use this information to reproduce the state of the real oracle. Initially, responses
        // from the ChainlinkAggregatorMock will match the real oracle.
        uint8 decimals = toMock.decimals();
        (, int256 currAnswer, , , ) = toMock.latestRoundData();

        ChainlinkAggregatorMock m = new ChainlinkAggregatorMock(
            decimals,
            currAnswer
        );
        vm.etch(address(toMock), address(m).code);

        // Now that the Original Oracle bytecode has been replaced with the mock oracle,
        // set the price of the mocked oracle to the original oracle price.
        mocked = ChainlinkAggregatorMock(address(toMock));
        mocked.setDecimals(decimals);
        mocked.updateAnswer(currAnswer);
    }
}

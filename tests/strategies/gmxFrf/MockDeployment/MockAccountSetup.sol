// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import { MockArbSys } from "../../../mocks/MockArbSys.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IWrappedNativeToken
} from "../../../../contracts/adapters/shared/interfaces/IWrappedNativeToken.sol";
import {
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    UpgradeableBeacon
} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {
    GmxFrfStrategyMetadata
} from "../GmxFrfStrategyMetadata.sol";

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
} from "../../../../contracts/interfaces/IInterestRateModel.sol";import {
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

import {MockRealtimeFeedVerifier} from "./MockRealtimeFeedVerifier.sol";

import {MockAccountExtension} from "./MockAccountExtension.sol";

import {
    StrategyController
} from "../../../../contracts/core/StrategyController.sol";

abstract contract MockAccountSetup is Test {
    // Steps
    // 1) Deploy Core / Strategy
    // 2) Etch Mock Oracle Feed Verifier To Deployed Address of Real Oracle Verifier

    IERC20 constant USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    IWrappedNativeToken constant WETH =
        IWrappedNativeToken(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    GmxFrfStrategyManager MANAGER;
    GmxFrfStrategyDeployer DEPLOYER;
    StrategyController CONTROLLER;
    IStrategyBank BANK;
    IStrategyReserve RESERVE;
    MockAccountExtension ACCOUNT;

    constructor() {
        _etchArbSys();
        _etchMockRealtimeFeedVerifier();
        _deployGmxFrfStrategy();
        _deployCore();
        _createAccount();
        _stealFunds();
    }

    function _etchArbSys() private {
        // Since foundry for some reason doesn't handle predeploys (even though they say they do);
        MockArbSys arbSys = new MockArbSys();
        vm.etch(
            address(0x0000000000000000000000000000000000000064),
            address(arbSys).code
        );
    }

    function _etchMockRealtimeFeedVerifier() private {
        MockRealtimeFeedVerifier verifier = new MockRealtimeFeedVerifier();
        vm.etch(
            address(0xa11B501c2dd83Acd29F6727570f2502FAaa617F2),
            address(verifier).code
        );
    }

    function _deployGmxFrfStrategy() private {
         address managerLogic = address(
            new GmxFrfStrategyManager(
                GmxFrfStrategyMetadata.USDC,
                GmxFrfStrategyMetadata.WETH,
               address(this)
            )
         );


        IDeploymentConfiguration.Deployments
            memory deployments = GmxFrfStrategyMetadata.getDeployments();

        IMarketConfiguration.SharedOrderParameters
            memory sharedOrderParameters = IMarketConfiguration
                .SharedOrderParameters(
                    1000000,
                    100000000000000000,
                    bytes32(0x676F6C646C696E6B000000000000000000000000000000000000000000000000),
                    0x62dF56DcEaaFEcBbb57D595E8Cf0b90cA437e77d,
                    1100000000000000000
                );

        IChainlinkAdapter.OracleConfiguration
            memory oracleConfiguration = IChainlinkAdapter.OracleConfiguration(
                100000,
                GmxFrfStrategyMetadata.USDC_USD_ORACLE
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
            new UpgradeableBeacon(
                accountLogic,
                address(this)
            )
        );

        DEPLOYER = new GmxFrfStrategyDeployer(
            accountBeacon
        );

    }



    function _deployCore() private {
        IStrategyBank.BankParameters memory bankParams = IStrategyBank.BankParameters(
            250000000000000000,
            166666666666666666,
            10000000000000000,
            50000000000000000,
            75000000000000000,
            10000000,
            DEPLOYER
        );

        IInterestRateModel.InterestRateModelParameters memory interestRateModel = IInterestRateModel.InterestRateModelParameters(
            900000000000000000,
            80000000000000000,
            1055600000000000,
            150000000000000000
        );


        IStrategyReserve.ReserveParameters memory reserveParams = IStrategyReserve.ReserveParameters(
            1000000000000,
            interestRateModel,
            "GoldLink GMX Funding Rate Farming Reserve Shares",
            "GFRF"
        );

         CONTROLLER = new StrategyController(
            address(this),
            GmxFrfStrategyMetadata.USDC,
            reserveParams,
            bankParams
        );

        BANK = CONTROLLER.STRATEGY_BANK();
        RESERVE = CONTROLLER.STRATEGY_RESERVE();
    }


    function _stealFunds() internal {
        vm.deal(address(this), 20 ether);
        GmxFrfStrategyMetadata.WETH.deposit{ value: 10 ether }();
        vm.prank(0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D);
        GmxFrfStrategyMetadata.USDC.transfer(address(address(this)), 1e13);
        vm.prank(0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D);
        GmxFrfStrategyMetadata.ARB.transfer(address(address(this)), 1e24);
        vm.prank(0x69eC552BE56E6505703f0C861c40039e5702037A);
        GmxFrfStrategyMetadata.WBTC.transfer(address(address(this)), 1e9);
    }

    function _createAccount() internal {
        ACCOUNT = MockAccountExtension(payable(BANK.executeOpenAccount(address(this))));
    }

    function _lendFunds(uint256 amount) internal {
        USDC.approve(address(RESERVE), amount);
        RESERVE.deposit(amount, address(this));
    }
}

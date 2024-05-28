// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    UpgradeableBeacon
} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IWrappedNativeToken
} from "../../contracts/adapters/shared/interfaces/IWrappedNativeToken.sol";
import {
    IDeploymentConfiguration
} from "../../contracts/strategies/gmxFrf/interfaces/IDeploymentConfiguration.sol";
import {
    IMarketConfiguration
} from "../../contracts/strategies/gmxFrf/interfaces/IMarketConfiguration.sol";
import {
    GmxFrfStrategyManager
} from "../../contracts/strategies/gmxFrf/GmxFrfStrategyManager.sol";
import {
    GmxFrfStrategyAccount
} from "../../contracts/strategies/gmxFrf/GmxFrfStrategyAccount.sol";
import {
    GmxFrfStrategyDeployer
} from "../../contracts/strategies/gmxFrf/GmxFrfStrategyDeployer.sol";
import {
    IGmxFrfStrategyManager
} from "../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";
import {
    IGmxV2ExchangeRouter
} from "../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2ExchangeRouter.sol";
import {
    IGmxV2Reader
} from "../../contracts/lib/gmx/interfaces/external/IGmxV2Reader.sol";
import {
    IGmxV2DataStore
} from "../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2RoleStore
} from "../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2RoleStore.sol";
import {
    IGmxV2ReferralStorage
} from "../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2ReferralStorage.sol";
import {
    IChainlinkAdapter
} from "../../contracts/adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import {
    IChainlinkAggregatorV3
} from "../../contracts/adapters/chainlink/interfaces/external/IChainlinkAggregatorV3.sol";

contract DeployStrategy is Script {
    string constant DEPLOYER_PRIVATE_KEY_ENV_KEY = "DEPLOYER_PRIVATE_KEY";
    string constant USDC_ADDRESS_ENV_KEY = "USDC_ADDRESS";
    string constant WRAPPED_NATIVE_ADDRESS_ENV_KEY = "WRAPPED_NATIVE_ADDRESS";
    string constant PROXY_ADMIN_ADDRESS_ENV_KEY = "PROXY_ADMIN_ADDRESS";
    string constant GMX_V2_EXCHANGE_ROUTER_ENV_KEY = "GMX_V2_EXCHANGE_ROUTER";
    string constant GMX_V2_ORDER_VAULT_ENV_KEY = "GMX_V2_ORDER_VAULT";
    string constant GMX_V2_READER_ENV_KEY = "GMX_V2_READER";
    string constant GMX_V2_DATASTORE_ENV_KEY = "GMX_V2_DATASTORE";
    string constant GMX_V2_ROLESTORE_ENV_KEY = "GMX_V2_ROLESTORE";
    string constant GMX_V2_REFERRAL_STORAGE_ENV_KEY = "GMX_V2_REFERRAL_STORAGE";
    string constant CALLBACK_GAS_LIMIT_ENV_KEY = "CALLBACK_GAS_LIMIT";
    string constant EXECUTION_FEE_BUFFER_PERCENT_ENV_KEY =
        "EXECUTION_FEE_BUFFER_PERCENT";
    string constant REFERRAL_CODE_ENV_KEY = "REFERRAL_CODE";
    string constant UI_FEE_RECEIVER_ENV_KEY = "UI_FEE_RECEIVER";
    string constant WITHDRAWAL_BUFFER_PERCENTAGE_ENV_KEY =
        "WITHDRAWAL_BUFFER_PERCENTAGE";
    string constant USDC_ORACLE_VALID_PRICE_DURATION_ENV_KEY =
        "USDC_ORACLE_VALID_PRICE_DURATION";
    string constant USDC_ORACLE_ADDRESS_ENV_KEY = "USDC_ORACLE_ADDRESS";
    string constant LIQUIDATION_ORDER_TIMEOUT_ENV_KEY =
        "LIQUIDATION_ORDER_TIMEOUT";

    function run() public {
        uint256 privateKey = vm.envUint(DEPLOYER_PRIVATE_KEY_ENV_KEY);

        vm.startBroadcast(privateKey);
        address managerLogic = address(
            new GmxFrfStrategyManager(
                IERC20(vm.envAddress(USDC_ADDRESS_ENV_KEY)),
                IWrappedNativeToken(
                    vm.envAddress(WRAPPED_NATIVE_ADDRESS_ENV_KEY)
                ),
                vm.envAddress(PROXY_ADMIN_ADDRESS_ENV_KEY)
            )
        );
        vm.stopBroadcast();

        IDeploymentConfiguration.Deployments
            memory deployments = IDeploymentConfiguration.Deployments(
                IGmxV2ExchangeRouter(
                    vm.envAddress(GMX_V2_EXCHANGE_ROUTER_ENV_KEY)
                ),
                vm.envAddress(GMX_V2_ORDER_VAULT_ENV_KEY),
                IGmxV2Reader(vm.envAddress(GMX_V2_READER_ENV_KEY)),
                IGmxV2DataStore(vm.envAddress(GMX_V2_DATASTORE_ENV_KEY)),
                IGmxV2RoleStore(vm.envAddress(GMX_V2_ROLESTORE_ENV_KEY)),
                IGmxV2ReferralStorage(
                    vm.envAddress(GMX_V2_REFERRAL_STORAGE_ENV_KEY)
                )
            );

        IMarketConfiguration.SharedOrderParameters
            memory sharedOrderParameters = IMarketConfiguration
                .SharedOrderParameters(
                    vm.envUint(CALLBACK_GAS_LIMIT_ENV_KEY),
                    vm.envUint(EXECUTION_FEE_BUFFER_PERCENT_ENV_KEY),
                    vm.envBytes32(REFERRAL_CODE_ENV_KEY),
                    vm.envAddress(UI_FEE_RECEIVER_ENV_KEY),
                    vm.envUint(WITHDRAWAL_BUFFER_PERCENTAGE_ENV_KEY)
                );

        IChainlinkAdapter.OracleConfiguration
            memory oracleConfiguration = IChainlinkAdapter.OracleConfiguration(
                vm.envUint(USDC_ORACLE_VALID_PRICE_DURATION_ENV_KEY),
                IChainlinkAggregatorV3(
                    vm.envAddress(USDC_ORACLE_ADDRESS_ENV_KEY)
                )
            );

        bytes memory initializerData = abi.encodeWithSelector(
            GmxFrfStrategyManager.initialize.selector,
            deployments,
            sharedOrderParameters,
            oracleConfiguration,
            vm.envUint(LIQUIDATION_ORDER_TIMEOUT_ENV_KEY)
        );

        vm.startBroadcast(privateKey);
        address managerProxy = address(
            new TransparentUpgradeableProxy(
                managerLogic,
                vm.envAddress(PROXY_ADMIN_ADDRESS_ENV_KEY), // initialOwner for the proxy admin
                initializerData
            )
        );
        vm.stopBroadcast();

        IGmxFrfStrategyManager manager = IGmxFrfStrategyManager(managerProxy);

        vm.startBroadcast(privateKey);
        address accountLogic = address(new GmxFrfStrategyAccount(manager));
        vm.stopBroadcast();

        vm.startBroadcast(privateKey);
        // Create upgradeable beacon pointing to that logic contract.
        address accountBeacon = address(
            new UpgradeableBeacon(
                accountLogic,
                vm.envAddress(PROXY_ADMIN_ADDRESS_ENV_KEY)
            )
        );
        vm.stopBroadcast();

        vm.startBroadcast(privateKey);
        // Deploy the account deployer.
        GmxFrfStrategyDeployer deployer = new GmxFrfStrategyDeployer(
            accountBeacon
        );
        vm.stopBroadcast();

        console.log("Manager Logic:", address(managerLogic));
        console.log("TransparentUpgradeableProxy", address(managerProxy));
        console.log("AccountDeployer", address(deployer));
        console.log("Beacon", accountBeacon);
    }
}

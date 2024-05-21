// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";

import {
    IMarketConfiguration
} from "../../contracts/strategies/gmxFrf/interfaces/IMarketConfiguration.sol";
import {
    GmxFrfStrategyDeployer
} from "../../contracts/strategies/gmxFrf/GmxFrfStrategyDeployer.sol";
import {
    IGmxFrfStrategyManager
} from "../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";
import {
    IChainlinkAdapter
} from "../../contracts/adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import {
    IChainlinkAggregatorV3
} from "../../contracts/adapters/chainlink/interfaces/external/IChainlinkAggregatorV3.sol";

contract SetMarket is Script {
    string constant DEPLOYER_PRIVATE_KEY_ENV_KEY = "DEPLOYER_PRIVATE_KEY";
    string constant MANAGER_ADDRESS_ENV_KEY = "MANAGER_ADDRESS";
    string constant MARKET_ADDRESS_ENV_KEY = "MARKET_ADDRESS";
    string constant ORACLE_VALID_PRICE_DURATION_ENV_KEY =
        "ORACLE_VALID_PRICE_DURATION";
    string constant ORACLE_ADDRESS_ENV_KEY = "ORACLE_ADDRESS";
    string constant MAX_SWAP_SLIPPAGE_PERCENT_ENV_KEY =
        "MAX_SWAP_SLIPPAGE_PERCENT";
    string constant MAX_POSITION_SLIPPAGE_PERCENT_ENV_KEY =
        "MAX_POSITION_SLIPPAGE_PERCENT";
    string constant MIN_ORDER_SIZE_USD_ENV_KEY = "MIN_ORDER_SIZE_USD";
    string constant MAX_ORDER_SIZE_USD_ENV_KEY = "MAX_ORDER_SIZE_USD";
    string constant INCREASE_ENABLED_ENV_KEY = "INCREASE_ENABLED";
    string constant MIN_POSITION_SIZE_USD_ENV_KEY = "MIN_POSITION_SIZE_USD";
    string constant MAX_POSITION_SIZE_USD_ENV_KEY = "MAX_POSITION_SIZE_USD";
    string constant MAX_DELTA_PROPORTION_ENV_KEY = "MAX_DELTA_PROPORTION";
    string constant MIN_SWAP_REBALANCE_SIZE_ENV_KEY = "MIN_SWAP_REBALANCE_SIZE";
    string constant MAX_POSITION_LEVERAGE_ENV_KEY = "MAX_POSITION_LEVERAGE";
    string constant UNWIND_FEE_ENV_KEY = "UNWIND_FEE";
    string constant LONG_TOKEN_LIQUIDATION_FEE_PERCENT_ENV_KEY =
        "LONG_TOKEN_LIQUIDATION_FEE_PERCENT";

    function run() public {
        uint256 privateKey = vm.envUint(DEPLOYER_PRIVATE_KEY_ENV_KEY);

        IChainlinkAdapter.OracleConfiguration
            memory oracleConfiguration = IChainlinkAdapter.OracleConfiguration(
                vm.envUint(ORACLE_VALID_PRICE_DURATION_ENV_KEY),
                IChainlinkAggregatorV3(vm.envAddress(ORACLE_ADDRESS_ENV_KEY))
            );

        IMarketConfiguration.OrderPricingParameters
            memory orderPricingParameters = IMarketConfiguration
                .OrderPricingParameters(
                    vm.envUint(MAX_SWAP_SLIPPAGE_PERCENT_ENV_KEY),
                    vm.envUint(MAX_POSITION_SLIPPAGE_PERCENT_ENV_KEY),
                    vm.envUint(MIN_ORDER_SIZE_USD_ENV_KEY),
                    vm.envUint(MAX_ORDER_SIZE_USD_ENV_KEY),
                    vm.envBool(INCREASE_ENABLED_ENV_KEY)
                );

        IMarketConfiguration.PositionParameters
            memory positionParameters = IMarketConfiguration.PositionParameters(
                vm.envUint(MIN_POSITION_SIZE_USD_ENV_KEY),
                vm.envUint(MAX_POSITION_SIZE_USD_ENV_KEY)
            );

        IMarketConfiguration.UnwindParameters
            memory unwindParameters = IMarketConfiguration.UnwindParameters(
                vm.envUint(MAX_DELTA_PROPORTION_ENV_KEY),
                vm.envUint(MIN_SWAP_REBALANCE_SIZE_ENV_KEY),
                vm.envUint(MAX_POSITION_LEVERAGE_ENV_KEY),
                vm.envUint(UNWIND_FEE_ENV_KEY)
            );

        vm.startBroadcast(privateKey);
        IGmxFrfStrategyManager(vm.envAddress(MANAGER_ADDRESS_ENV_KEY))
            .setMarket(
                vm.envAddress(MARKET_ADDRESS_ENV_KEY),
                oracleConfiguration,
                orderPricingParameters,
                positionParameters,
                unwindParameters,
                vm.envUint(LONG_TOKEN_LIQUIDATION_FEE_PERCENT_ENV_KEY)
            );
        vm.stopBroadcast();
    }
}

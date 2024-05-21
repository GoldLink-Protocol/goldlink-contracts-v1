// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    IChainlinkAdapter
} from "../../../contracts/adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TestUtilities } from "../../testLibraries/TestUtilities.sol";
import {
    IGmxFrfStrategyManager
} from "../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";
import {
    IDeploymentConfiguration
} from "../../../contracts/strategies/gmxFrf/interfaces/IDeploymentConfiguration.sol";

import {
    IGmxV2ExchangeRouter
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2ExchangeRouter.sol";
import {
    IGmxV2Reader
} from "../../../contracts/lib/gmx/interfaces/external/IGmxV2Reader.sol";
import {
    IGmxV2DataStore
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2RoleStore
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2RoleStore.sol";
import {
    IGmxV2OrderTypes
} from "../../../contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import {
    IGmxV2ReferralStorage
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2ReferralStorage.sol";
import {
    IChainlinkAggregatorV3
} from "../../../contracts/adapters/chainlink/interfaces/external/IChainlinkAggregatorV3.sol";
import {
    IWrappedNativeToken
} from "../../../contracts/adapters/shared/interfaces/IWrappedNativeToken.sol";

library GmxFrfStrategyMetadata {
    IERC20 constant USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    IWrappedNativeToken constant WETH =
        IWrappedNativeToken(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    IERC20 constant WBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);

    IERC20 constant ARB = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);

    address constant GMX_V2_ETH_USDC =
        0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;

    address constant GMX_V2_ARB_USDC_MARKET =
        0xC25cEf6061Cf5dE5eb761b50E4743c1F5D7E5407;

    address constant GMX_V2_WBTC_USDC_MARKET =
        0x47c031236e19d024b42f8AE6780E44A573170703;

    IChainlinkAggregatorV3 constant USDC_USD_ORACLE =
        IChainlinkAggregatorV3(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);

    IChainlinkAggregatorV3 constant ARB_USD_ORACLE =
        IChainlinkAggregatorV3(0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6);

    IChainlinkAggregatorV3 constant ETH_USD_ORACLE =
        IChainlinkAggregatorV3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);

    IChainlinkAggregatorV3 constant BTC_USD_ORACLE =
        IChainlinkAggregatorV3(0x6ce185860a4963106506C203335A2910413708e9);

    IGmxV2ExchangeRouter constant GMX_V2_EXCHANGE_ROUTER =
        IGmxV2ExchangeRouter(0x7C68C7866A64FA2160F78EEaE12217FFbf871fa8);

    IGmxV2Reader constant GMX_V2_READER =
        IGmxV2Reader(0x60a0fF4cDaF0f6D496d71e0bC0fFa86FE8E6B23c);

    IGmxV2DataStore constant GMX_V2_DATASTORE =
        IGmxV2DataStore(0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8);

    IGmxV2RoleStore constant GMX_V2_ROLESTORE =
        IGmxV2RoleStore(0x3c3d99FD298f679DBC2CEcd132b4eC4d0F5e6e72);

    IGmxV2ReferralStorage constant GMX_V2_REFERRAL_STORAGE =
        IGmxV2ReferralStorage(0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d);

    address constant GMX_V2_ORDER_VAULT =
        0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5;

    function getDeployments()
        internal
        pure
        returns (IDeploymentConfiguration.Deployments memory)
    {
        return
            IDeploymentConfiguration.Deployments(
                GMX_V2_EXCHANGE_ROUTER,
                GMX_V2_ORDER_VAULT,
                GMX_V2_READER,
                GMX_V2_DATASTORE,
                GMX_V2_ROLESTORE,
                GMX_V2_REFERRAL_STORAGE
            );
    }

    address constant GMX_ORDER_KEEPER_PRANK =
        0xC539cB358a58aC67185BaAD4d5E3f7fCfc903700;
}

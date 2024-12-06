// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IDeploymentConfiguration
} from "../../../../contracts/strategies/gmxFrf/interfaces/IDeploymentConfiguration.sol";
import {
    IGmxV2ExchangeRouter
} from "../../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2ExchangeRouter.sol";
import {
    IGmxV2Reader
} from "../../../../contracts/lib/gmx/interfaces/external/IGmxV2Reader.sol";
import {
    IGmxV2DataStore
} from "../../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2RoleStore
} from "../../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2RoleStore.sol";
import {
    IGmxV2OrderTypes
} from "../../../../contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import {
    IGmxV2ReferralStorage
} from "../../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2ReferralStorage.sol";
import {
    IChainlinkAggregatorV3
} from "../../../../contracts/adapters/chainlink/interfaces/external/IChainlinkAggregatorV3.sol";
import {
    IWrappedNativeToken
} from "../../../../contracts/adapters/shared/interfaces/IWrappedNativeToken.sol";
import { IOrderHandler } from "./IOrderHandler.sol";
import {
    IUniversalRouter
} from "@periphery/contracts/liquidation/interfaces/uniswap/IUniversalRouter.sol";
import {
    IUniswapV3PoolActions
} from "@periphery/contracts/liquidation/interfaces/uniswap/IUniswapV3PoolActions.sol";

abstract contract GmxFrfStrategyMetadata {
    // Token Addresses
    IERC20 constant USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    IWrappedNativeToken constant WETH =
        IWrappedNativeToken(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 constant WBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20 constant ARB = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
    IERC20 constant LINK = IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);
    IERC20 constant GMX = IERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);

    // Uniswap Addresses
    IUniversalRouter UNIVERSAL_ROUTER =
        IUniversalRouter(0x4C60051384bd2d3C01bfc845Cf5F4b44bcbE9de5);
    IUniswapV3PoolActions WETH_USDC_UNIV3 =
        IUniswapV3PoolActions(0xC6962004f452bE9203591991D15f6b388e09E8D0);
    IUniswapV3PoolActions ARB_USDC_UNIV3 =
        IUniswapV3PoolActions(0xb0f6cA40411360c03d41C5fFc5F179b8403CdcF8);
    IUniswapV3PoolActions WBTC_USDC_UNIV3 =
        IUniswapV3PoolActions(0x0E4831319A50228B9e450861297aB92dee15B44F);
    IUniswapV3PoolActions LINK_USDC_UNIV3 =
        IUniswapV3PoolActions(0x655C1607F8c2E73D5b4ddAbCe9Ba8792b87592B6);
    IUniswapV3PoolActions GMX_USDC_UNIV3 =
        IUniswapV3PoolActions(0x135E49cC315fED87F989e072ee11132686CF84F3);

    // GM Market Addresses
    address constant ETH_USD_MARKET =
        0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
    address constant ARB_USD_MARKET =
        0xC25cEf6061Cf5dE5eb761b50E4743c1F5D7E5407;
    address constant WBTC_USD_MARKET =
        0x47c031236e19d024b42f8AE6780E44A573170703;
    address constant LINK_USD_MARKET =
        0x47c031236e19d024b42f8AE6780E44A573170703;
    address constant GMX_USD_MARKET =
        0x55391D178Ce46e7AC8eaAEa50A72D1A5a8A622Da;

    // Oracle Addresses
    IChainlinkAggregatorV3 constant USDC_USD_ORACLE =
        IChainlinkAggregatorV3(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);
    IChainlinkAggregatorV3 constant ARB_USD_ORACLE =
        IChainlinkAggregatorV3(0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6);
    IChainlinkAggregatorV3 constant ETH_USD_ORACLE =
        IChainlinkAggregatorV3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
    IChainlinkAggregatorV3 constant BTC_USD_ORACLE =
        IChainlinkAggregatorV3(0x6ce185860a4963106506C203335A2910413708e9);
    IChainlinkAggregatorV3 constant LINK_USD_ORACLE =
        IChainlinkAggregatorV3(0x86E53CF1B870786351Da77A57575e79CB55812CB);
    IChainlinkAggregatorV3 constant GMX_USD_ORACLE =
        IChainlinkAggregatorV3(0xDB98056FecFff59D032aB628337A4887110df3dB);

    // GMX Deployment Addresses
    IGmxV2ExchangeRouter constant GMX_EXCHANGE_ROUTER =
        IGmxV2ExchangeRouter(0x900173A66dbD345006C51fA35fA3aB760FcD843b);
    IGmxV2Reader constant GMX_READER =
        IGmxV2Reader(0x5Ca84c34a381434786738735265b9f3FD814b824);
    IGmxV2DataStore constant GMX_DATASTORE =
        IGmxV2DataStore(0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8);
    IGmxV2RoleStore constant GMX_ROLESTORE =
        IGmxV2RoleStore(0x3c3d99FD298f679DBC2CEcd132b4eC4d0F5e6e72);
    IGmxV2ReferralStorage constant GMX_REFERRAL_STORAGE =
        IGmxV2ReferralStorage(0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d);
    address constant GMX_ORDER_VAULT =
        0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5;
    IOrderHandler GMX_ORDER_HANDLER =
        IOrderHandler(0xe68CAAACdf6439628DFD2fe624847602991A31eB);

    // GMX Keeper Signer Address
    address constant GMX_ORACLE_SIGNER =
        0xC539cB358a58aC67185BaAD4d5E3f7fCfc903700;

    address constant GMX_CONTROLLER =
        0xe68CAAACdf6439628DFD2fe624847602991A31eB;

    address constant MSIG = 0x62dF56DcEaaFEcBbb57D595E8Cf0b90cA437e77d;

    function getDeployments()
        internal
        pure
        returns (IDeploymentConfiguration.Deployments memory)
    {
        return
            IDeploymentConfiguration.Deployments(
                GMX_EXCHANGE_ROUTER,
                GMX_ORDER_VAULT,
                GMX_READER,
                GMX_DATASTORE,
                GMX_ROLESTORE,
                GMX_REFERRAL_STORAGE
            );
    }
}

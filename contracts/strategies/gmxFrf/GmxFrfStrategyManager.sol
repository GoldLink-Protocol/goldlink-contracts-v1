// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {
    GoldLinkOwnableUpgradeable
} from "../../utils/GoldLinkOwnableUpgradeable.sol";
import {
    MarketConfigurationManager
} from "./configuration/MarketConfigurationManager.sol";
import {
    DeploymentConfigurationManager
} from "./configuration/DeploymentConfigurationManager.sol";
import {
    IChainlinkAdapter
} from "../../adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import {
    OracleAssetRegistry
} from "../../adapters/chainlink/OracleAssetRegistry.sol";
import {
    IGmxFrfStrategyManager
} from "./interfaces/IGmxFrfStrategyManager.sol";
import {
    IGmxV2ExchangeRouter
} from "../../strategies/gmxFrf/interfaces/gmx/IGmxV2ExchangeRouter.sol";
import {
    IGmxV2Reader
} from "../../lib/gmx/interfaces/external/IGmxV2Reader.sol";
import {
    IGmxV2DataStore
} from "../../strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2RoleStore
} from "../../strategies/gmxFrf/interfaces/gmx/IGmxV2RoleStore.sol";
import {
    IGmxV2ReferralStorage
} from "../../strategies/gmxFrf/interfaces/gmx/IGmxV2ReferralStorage.sol";
import {
    IGmxV2MarketTypes
} from "../../strategies/gmxFrf/interfaces/gmx/IGmxV2MarketTypes.sol";
import {
    IWrappedNativeToken
} from "../../adapters/shared/interfaces/IWrappedNativeToken.sol";
import { GmxFrfStrategyErrors } from "./GmxFrfStrategyErrors.sol";
import { Limits } from "./libraries/Limits.sol";

/**
 * @title GmxFrfStrategyManager
 * @author GoldLink
 *
 * @notice Contract that deploys new strategy accounts for the GMX funding rate farming strategy.
 */
contract GmxFrfStrategyManager is
    IGmxFrfStrategyManager,
    DeploymentConfigurationManager,
    MarketConfigurationManager,
    OracleAssetRegistry,
    GoldLinkOwnableUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Constructor ============

    /**
     * @notice Constructor for upgradeable contract, distinct from initializer.
     *
     *  The constructor is used to set immutable variables, and for top-level upgradeable
     *  contracts, it is also used to disable the initializer of the logic contract.
     */
    constructor(
        IERC20 strategyAsset,
        IWrappedNativeToken wrappedNativeToken,
        address collateralClaimDistributor
    )
        DeploymentConfigurationManager(
            strategyAsset,
            wrappedNativeToken,
            collateralClaimDistributor
        )
    {
        _disableInitializers();
    }

    // ============ Initializer ============

    function initialize(
        Deployments calldata deployments,
        SharedOrderParameters calldata sharedOrderParameters,
        IChainlinkAdapter.OracleConfiguration
            calldata strategyAssetOracleConfig,
        uint256 liquidationOrderTimeoutDeadline
    ) external initializer {
        __Ownable_init(msg.sender);
        __DeploymentConfigurationManager_init(deployments);
        __MarketConfigurationManager_init(
            sharedOrderParameters,
            liquidationOrderTimeoutDeadline
        );
        __OracleAssetRegistry_init(address(USDC), strategyAssetOracleConfig);
    }

    // ============ External Functions ============

    function setExchangeRouter(
        IGmxV2ExchangeRouter exchangeRouter
    ) external override onlyOwner onlyNonZeroAddress(address(exchangeRouter)) {
        _setExchangeRouter(exchangeRouter);
    }

    function setOrderVault(
        address orderVault
    ) external override onlyOwner onlyNonZeroAddress(orderVault) {
        _setOrderVault(orderVault);
    }

    function setReader(
        IGmxV2Reader reader
    ) external override onlyOwner onlyNonZeroAddress(address(reader)) {
        _setReader(reader);
    }

    function setDataStore(
        IGmxV2DataStore dataStore
    ) external override onlyOwner onlyNonZeroAddress(address(dataStore)) {
        _setDataStore(dataStore);
    }

    function setRoleStore(
        IGmxV2RoleStore roleStore
    ) external override onlyOwner onlyNonZeroAddress(address(roleStore)) {
        _setRoleStore(roleStore);
    }

    function setReferralStorage(
        IGmxV2ReferralStorage referralStorage
    ) external override onlyOwner onlyNonZeroAddress(address(referralStorage)) {
        _setReferralStorage(referralStorage);
    }

    /**
     * @notice Sets the market configuration for the specified `marketAddress`. Will overwrite the existing configuration. The function should be
     * guarded by a timelock, or changes should be announced in advance, to ensure that any account that may be effected has ample amount of time to adjust their position accordingly
     * in the event that a parameter change puts their position at risk.
     * @param marketAddress                  The address of the market being set.
     * @param oracleConfig                   The configuration for the oracle for the long token of this market.
     * @param marketParameters               The parameters for the newly added market.
     * @param positionParameters             The parameters for maintaining a position.
     * @param unwindParameters               The parameters for unwinding a position.
     * @param longTokenLiquidationFeePercent The fee for liquidating a position.
     */
    function setMarket(
        address marketAddress,
        IChainlinkAdapter.OracleConfiguration calldata oracleConfig,
        OrderPricingParameters calldata marketParameters,
        PositionParameters calldata positionParameters,
        UnwindParameters calldata unwindParameters,
        uint256 longTokenLiquidationFeePercent
    ) external override onlyOwner {
        // Get the market from the GMX V2 Reader to validate the state of the market.
        IGmxV2MarketTypes.Props memory market = gmxV2Reader().getMarket(
            gmxV2DataStore(),
            marketAddress
        );

        // Make sure the short token is USDC, also ensures the market exists otherwise
        // the short token would be the zero address.
        require(
            market.shortToken == address(USDC),
            GmxFrfStrategyErrors
                .GMX_FRF_STRATEGY_MANAGER_SHORT_TOKEN_MUST_BE_USDC
        );

        // Sanity check.
        require(
            market.longToken != address(USDC),
            GmxFrfStrategyErrors.LONG_TOKEN_CANT_BE_USDC
        );

        // Check to make sure we are either modifying an existing asset's oracle or adding
        // a new oracle. The asset oracle length must be limited to prevent the admin adding
        // a lot of asset oracles, making it impossible for a strategy account to be liquidated
        // or repay it's loan due to out of gas errors when calling `getAccountValue()`.
        require(
            registeredAssets_.contains(market.longToken) ||
                registeredAssets_.length() < Limits.MAX_REGISTERED_ASSET_COUNT,
            GmxFrfStrategyErrors.ASSET_ORACLE_COUNT_CANNOT_EXCEED_MAXIMUM
        );

        // Get all markets so we can check that there is no market with a different address
        // that has the same long token. This prevents double counting the value of assets.
        address[] memory markets = getAvailableMarkets();

        uint256 marketsLength = markets.length;
        for (uint256 i = 0; i < marketsLength; ++i) {
            address marketAddressToCheck = markets[i];
            if (marketAddressToCheck == marketAddress) {
                // If the market already exists, it implies this check already passed
                // successfully.
                break;
            }

            IGmxV2MarketTypes.Props memory marketToCheck = gmxV2Reader()
                .getMarket(gmxV2DataStore(), marketAddressToCheck);

            // Check to make sure the market we are checking, which at this point is a different address than the market being added,
            // does not have the same long token. This can occur if GMX decides to upgrade market contracts, so it must be validated.
            require(
                marketToCheck.longToken != market.longToken,
                GmxFrfStrategyErrors
                    .CANNOT_ADD_SEPERATE_MARKET_WITH_SAME_LONG_TOKEN
            );
        }

        _setAssetOracle(
            market.longToken,
            oracleConfig.oracle,
            oracleConfig.validPriceDuration
        );

        // Set the market configuration.
        _setMarketConfiguration(
            marketAddress,
            marketParameters,
            positionParameters,
            unwindParameters
        );

        // Set the liquidation fee for the long token.
        _setAssetLiquidationFeePercent(
            market.longToken,
            longTokenLiquidationFeePercent
        );
    }

    /**
     * @notice Update the USDC oracle. Gives admin the ability to update the USDC oracle should
     * it change upstream.
     * @param strategyAssetOracleConfig The updated configuration for the USDC oracle.
     */
    function updateUsdcOracle(
        IChainlinkAdapter.OracleConfiguration calldata strategyAssetOracleConfig
    ) external override onlyOwner {
        _setAssetOracle(
            address(USDC),
            strategyAssetOracleConfig.oracle,
            strategyAssetOracleConfig.validPriceDuration
        );
    }

    /**
     * @notice Disables all increase orders in a market. This function is provided so the timelock contract that owns the GmxFrfStrategyManager can
     * instantly disable increase orders in a market in the event of severe protocol malfunction that require immediate attention. This function should not
     * be timelocked, as it only prevents borrowers from increasing exposure to a given market. All decrease functionality remains possible.
     * Note that is still possible to disable market increases via `setMarket`.
     * @param marketAddress       The address of the market being added.
     */
    function disableMarketIncreases(
        address marketAddress
    ) external override onlyOwner {
        // Make sure the market actually exists.
        require(
            isApprovedMarket(marketAddress),
            GmxFrfStrategyErrors.MARKET_IS_NOT_ENABLED
        );

        MarketConfiguration memory config = getMarketConfiguration(
            marketAddress
        );

        // Make sure that increases are not already disabled.
        require(
            config.orderPricingParameters.increaseEnabled,
            GmxFrfStrategyErrors.MARKET_INCREASES_ARE_ALREADY_DISABLED
        );

        // Set `increaseEnabled` to false, preventing increase orders from being created. Pending increase orders will still be executed.
        config.orderPricingParameters.increaseEnabled = false;

        _setMarketConfiguration(
            marketAddress,
            config.orderPricingParameters,
            config.positionParameters,
            config.unwindParameters
        );
    }

    /**
     * @notice Set the asset liquidation fee percent for a specific asset. There is a maximum fee
     * of 10% (1e17) to prevent a bad owner from stealing all assets in an account.
     * @param asset                    The asset to set the liquidation fee for.
     * @param newLiquidationFeePercent The fee percentage that is paid to liquidators when selling this asset.
     */
    function setAssetLiquidationFee(
        address asset,
        uint256 newLiquidationFeePercent
    ) external override onlyOwner {
        _setAssetLiquidationFeePercent(asset, newLiquidationFeePercent);
    }

    /**
     * @notice Set the liquidation order timeout deadline, which is the amount of time that must pass before
     * a liquidation order can be cancelled.
     * @param newLiquidationOrderTimeoutDeadline The new liquidation order timeout to use for all liquidation orders.
     */
    function setLiquidationOrderTimeoutDeadline(
        uint256 newLiquidationOrderTimeoutDeadline
    ) external override onlyOwner {
        _setLiquidationOrderTimeoutDeadline(newLiquidationOrderTimeoutDeadline);
    }

    /**
     * @notice Set the callback gas limit for the strategy. Setting this value too low results in callback
     * execution failures which must be avoided. Setting this value too high
     * requires the user to provide a higher execution fee, which will ultimately be rebated if not used.
     * A configured limit prevents the owner from setting a large callback limit to prevent orders from being placed.
     * @param newCallbackGasLimit The callback gas limit to provide for all orders.
     */
    function setCallbackGasLimit(
        uint256 newCallbackGasLimit
    ) external override onlyOwner {
        _setCallbackGasLimit(newCallbackGasLimit);
    }

    /**
     * @notice Set the execution fee buffer percentage for the strategy. This is the percentage of the initially
     * calculated execution fee that needs to be provided additionally to prevent orders from failing execution.
     * The value of the execution fee buffer percentage should account for possible shifts in gas price between
     * order creation and keeper execution. A higher value will result in a higher execution fee being required
     * by the user. As such, a configured maximum value is checked against when setting this configuration variable
     * to prevent the owner from setting a high fee that prevents accounts from creating orders.
     * @param newExecutionFeeBufferPercent The new execution fee buffer percentage.
     */
    function setExecutionFeeBufferPercent(
        uint256 newExecutionFeeBufferPercent
    ) external override onlyOwner {
        _setExecutionFeeBufferPercent(newExecutionFeeBufferPercent);
    }

    /**
     * @notice Set the referral code to use for all orders.
     * @param newReferralCode The new referral code to use for all orders.
     */
    function setReferralCode(
        bytes32 newReferralCode
    ) external override onlyOwner {
        _setReferralCode(newReferralCode);
    }

    /**
     * @notice Set the ui fee receiver to use for all orders.
     * @param newUiFeeReceiver The new ui fee receiver to use for all orders.
     */
    function setUiFeeReceiver(
        address newUiFeeReceiver
    ) external override onlyOwner {
        _setUiFeeReceiver(newUiFeeReceiver);
    }

    /**
     * @notice Sets the withdrawal buffer percentage. There is a configured minimum to prevent the owner from allowing accounts
     * to withdraw funds that bring the account's value below the loan. There is no maximum because it may be neccesary in
     * extreme circumstances for the owner to disable withdrawals while a loan is active by setting a higher limit.
     * It is always possible to withdraw funds once the loan is repaid, so this does not lock user funds permanantly.
     * A `withdrawalBufferPercentage` of 1.1e18 (110%) implies that the value of an account after withdrawing funds
     * must be greater than the `1.1 * loan` for a given account.
     * @param newWithdrawalBufferPercentage The new withdrawal buffer percentage.
     */
    function setWithdrawalBufferPercentage(
        uint256 newWithdrawalBufferPercentage
    ) external override onlyOwner {
        _setWithdrawalBufferPercentage(newWithdrawalBufferPercentage);
    }
}

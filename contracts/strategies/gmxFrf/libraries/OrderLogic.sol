// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    IGmxV2RoleStore
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2RoleStore.sol";
import {
    IGmxV2OrderTypes
} from "../../../lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import {
    IGmxV2EventUtilsTypes
} from "../../../lib/gmx/interfaces/external/IGmxV2EventUtilsTypes.sol";
import { Order } from "../../../lib/gmx/order/Order.sol";
import { OrderStoreUtils } from "../../../lib/gmx/order/OrderStoreUtils.sol";
import {
    GmxStorageGetters
} from "../../../strategies/gmxFrf/libraries/GmxStorageGetters.sol";
import {
    GmxMarketGetters
} from "../../../strategies/gmxFrf/libraries/GmxMarketGetters.sol";
import { OrderValidation } from "../libraries/OrderValidation.sol";
import {
    PositionStoreUtils
} from "../../../lib/gmx/position/PositionStoreUtils.sol";
import {
    IGmxV2PositionTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";
import {
    IGmxFrfStrategyManager
} from "../interfaces/IGmxFrfStrategyManager.sol";
import {
    IGmxV2DataStore
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2MarketTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2MarketTypes.sol";
import { PercentMath } from "../../../libraries/PercentMath.sol";
import {
    IWrappedNativeToken
} from "../../../adapters/shared/interfaces/IWrappedNativeToken.sol";
import { Pricing } from "../libraries/Pricing.sol";
import { OrderHelpers } from "../libraries/OrderHelpers.sol";
import { DeltaConvergenceMath } from "../libraries/DeltaConvergenceMath.sol";
import { GmxFrfStrategyErrors } from "../GmxFrfStrategyErrors.sol";

/**
 * @title OrderLogic
 * @author GoldLink
 *
 * @dev Manages all orders that flow through this account, ensuring they remain delta neutral.
 */
library OrderLogic {
    using PercentMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IWrappedNativeToken;

    // ============ Structs ============

    /// @dev Struct that keeps track of pending liquidations.
    /// @param feesOwedUsd The amount of fees owed in USD. This is calculated in USD because it is possible to recieve multiple assets
    /// from a GMX collateral swap, in the event of a liquidation.
    /// @param feeRecipient The address that should recieve the fees owed.
    struct PendingLiquidation {
        uint256 feesOwedUsd;
        address feeRecipient;
        uint64 orderTimestamp;
    }

    // ============ External Functions ============

    /**
     * @notice Creates an increase order via GMX's contracts to increase an account's position in a given market. Given a provided `collateralAmount`,
     * it calculates the size of the perpetual short that should be entered to properly hedge the order. An execution fee must be provided that is used to pay GMX keepers.
     * The remainder of that execution fee is refunded to the order creator after execution.
     * @param manager                 The configuration manager for the strategy.
     * @param executionFeeRecipients_ Storage pointer to the executionFeeRecipients mapping.
     * @param market                  The market to create the order in. Must be approved by the manager.
     * @param collateralAmount        The amount of `USDC` that should be used to purchase the `longToken` of the specified market.
     * This will be used as collateral for the perpetual short position.
     * @param executionFee            The gas stipend for executing the transfer.
     * @return order                  The increase order that was created via GMX.
     * @return orderKey               The key for the order.
     */
    function createIncreaseOrder(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => address) storage executionFeeRecipients_,
        address market,
        uint256 collateralAmount,
        uint256 executionFee
    )
        external
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        )
    {
        // The configuration is what determines whether an order is valid.
        IGmxFrfStrategyManager.MarketConfiguration memory marketConfig = manager
            .getMarketConfiguration(market);

        IGmxV2DataStore dataStore = manager.gmxV2DataStore();

        // Validate order type is enabled.
        OrderValidation.validateOrdersEnabled(
            marketConfig.orderPricingParameters.increaseEnabled
        );

        // Validate that the account has no pending orders.
        OrderValidation.validateNoPendingOrdersInMarket(dataStore, market);

        IGmxV2MarketTypes.Props memory marketInfo = GmxMarketGetters.getMarket(
            dataStore,
            market
        );

        // Validate that the initial collateral token balance is greater than or equal to the delta
        // that would take place. I.e. make sure they have enough USDC.
        uint256 initialCollateralBalance = IERC20(marketInfo.shortToken)
            .balanceOf(address(this));
        require(
            initialCollateralBalance >= collateralAmount,
            GmxFrfStrategyErrors
                .ORDER_VALIDATION_INITIAL_COLLATERAL_BALANCE_IS_TOO_LOW
        );

        // Get the short and long token price for the market the order is being placed in.
        (uint256 shortTokenPrice, uint256 longTokenPrice) = DeltaConvergenceMath
            .getMarketPrices(
                manager,
                marketInfo.shortToken,
                marketInfo.longToken
            );

        DeltaConvergenceMath.IncreasePositionResult memory result;

        {
            DeltaConvergenceMath.DeltaCalculationParameters
                memory values = DeltaConvergenceMath
                    .DeltaCalculationParameters({
                        marketAddress: market,
                        account: address(this),
                        shortTokenPrice: shortTokenPrice,
                        longTokenPrice: longTokenPrice,
                        uiFeeReceiver: marketConfig
                            .sharedOrderParameters
                            .uiFeeReceiver,
                        market: marketInfo
                    });

            result = DeltaConvergenceMath.getIncreaseOrderValues(
                manager,
                collateralAmount,
                values
            );
        }

        order.numbers.acceptablePrice = OrderHelpers
            .getMinimumAcceptablePriceForIncrease(
                longTokenPrice,
                marketConfig.orderPricingParameters.maxPositionSlippagePercent
            );

        // Validate the order price. We do not care about the minimum slippage for increase orders because we can guarantee they will go through with
        // our specified parameters.
        OrderValidation.validateIncreaseOrderPrice(
            result.executionPrice,
            order.numbers.acceptablePrice
        );

        order.numbers.initialCollateralDeltaAmount = collateralAmount;
        order.numbers.minOutputAmount = OrderHelpers
            .getMinimumSwapOutputWithSlippage(
                result.swapOutputMarkedToMarket,
                marketConfig.orderPricingParameters.maxSwapSlippagePercent
            );

        // Validate the swap slippage.
        OrderValidation.validateSwapSlippage(
            result.swapOutputTokens,
            order.numbers.minOutputAmount
        );

        order.numbers.sizeDeltaUsd = result.sizeDeltaUsd;

        // Validate the order size.
        // There is a minimum order size to prevent small positions
        // from being unprofitable to rebalance/liquidate resulting in bad debt.
        // The maximum is to limit price impact as well.
        OrderValidation.validateOrderSize(
            marketConfig.orderPricingParameters.minOrderSizeUsd,
            marketConfig.orderPricingParameters.maxOrderSizeUsd,
            order.numbers.sizeDeltaUsd
        );

        // Validate the position size.
        // The position size must be within the min/max bounds.
        // The position size is the open interest in USD and does not represent the current value of the position.
        OrderValidation.validatePositionSize(
            marketConfig.positionParameters.minPositionSizeUsd,
            marketConfig.positionParameters.maxPositionSizeUsd,
            result.positionSizeNextUsd
        );

        // Set the order type.
        order.orderType = IGmxV2OrderTypes.OrderType.MarketIncrease;

        // If the position is experiences liquidation/adl, this ensures we recieve the output in USDC and therefore do not end
        // up with positive delta.
        order.decreasePositionSwapType = IGmxV2OrderTypes
            .DecreasePositionSwapType
            .SwapCollateralTokenToPnlToken;

        // Set the referral code, which gives rebates.
        order.referralCode = marketConfig.sharedOrderParameters.referralCode;

        order.addresses = OrderHelpers.createOrderAddresses(
            market,
            // Traditional increase orders (i.e. not rebalacing ones) always use USDC as the initial collateral.
            marketInfo.shortToken,
            marketConfig.sharedOrderParameters.uiFeeReceiver,
            true
        );

        // Set the callback gas limit and execution fee for the order.
        order.numbers.callbackGasLimit = marketConfig
            .sharedOrderParameters
            .callbackGasLimit;
        order.numbers.executionFee = executionFee;

        // Validate the provided execution fee.
        OrderValidation.validateExecutionFee(
            dataStore,
            order.orderType,
            order.addresses.swapPath.length,
            order.numbers.callbackGasLimit,
            marketConfig.sharedOrderParameters.executionFeeBufferPercent,
            tx.gasprice,
            order.numbers.executionFee
        );

        return (
            order,
            sendOrder(manager, executionFeeRecipients_, order, executionFee)
        );
    }

    /**
     * @notice Creates a decrease order, with the specified `sizeDeltaUSD`. This decreases the position's size and sells off collateral to ensure the position's delta is balanced.
     * An Execution fee must be provided to pay the GMX keeper, the remainder of the execution fee is refunded after order execution occurs.
     * @param manager                 The configuration manager for the strategy.
     * @param executionFeeRecipients_ Storage pointer to the executionFeeRecipients mapping.
     * @param market                  The market to decrease the size of the order in.
     * @param sizeDeltaUsd            The size, in terms of USD, that should be decreased from the position. Passing in `0` will settle funding fees and balance the position.
     * @param executionFee            The gas stipend for executing the transfer.
     * @return order                  The decrease order that was created via GMX.
     * @return orderKey               The key for the order.
     */
    function createDecreaseOrder(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => address) storage executionFeeRecipients_,
        address market,
        uint256 sizeDeltaUsd,
        uint256 executionFee
    )
        external
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        )
    {
        // The configuration is what determines whether an order is valid.
        IGmxFrfStrategyManager.MarketConfiguration memory marketConfig = manager
            .getMarketConfiguration(market);

        IGmxV2DataStore dataStore = manager.gmxV2DataStore();

        // Validate that the account has no pending orders. We cannot calculate the correct position delta if there exist pending orders.
        OrderValidation.validateNoPendingOrdersInMarket(dataStore, market);

        // Validate that a position exists.
        OrderValidation.validatePositionExists(dataStore, market);

        IGmxV2MarketTypes.Props memory marketInfo = GmxMarketGetters.getMarket(
            dataStore,
            market
        );

        // Get the short and long token price for the market the order is being placed in.
        (uint256 shortTokenPrice, uint256 longTokenPrice) = DeltaConvergenceMath
            .getMarketPrices(
                manager,
                marketInfo.shortToken,
                marketInfo.longToken
            );

        DeltaConvergenceMath.DeltaCalculationParameters
            memory values = DeltaConvergenceMath.DeltaCalculationParameters({
                marketAddress: market,
                account: address(this),
                shortTokenPrice: shortTokenPrice,
                longTokenPrice: longTokenPrice,
                uiFeeReceiver: marketConfig.sharedOrderParameters.uiFeeReceiver,
                market: marketInfo
            });

        DeltaConvergenceMath.DecreasePositionResult
            memory result = DeltaConvergenceMath.getDecreaseOrderValues(
                manager,
                sizeDeltaUsd,
                values
            );

        order.numbers.acceptablePrice = OrderHelpers
            .getMaximumAcceptablePriceForDecrease(
                longTokenPrice,
                marketConfig.orderPricingParameters.maxPositionSlippagePercent
            );

        // Validate the order price.
        OrderValidation.validateDecreaseOrderPrice(
            result.executionPrice,
            order.numbers.acceptablePrice
        );

        // This must be a USD value per the spec.
        order.numbers.initialCollateralDeltaAmount = result.collateralToRemove;
        order.numbers.minOutputAmount = OrderHelpers
            .getMinimumSwapOutputWithSlippage(
                result.estimatedOutputUsd,
                marketConfig.orderPricingParameters.maxSwapSlippagePercent
            );

        order.numbers.sizeDeltaUsd = sizeDeltaUsd;

        if (result.positionSizeNextUsd != 0 && sizeDeltaUsd != 0) {
            // Validate the order size. Only do this if remainingPositionSize != 0, since it may be impossible to
            // reduce the position size in the event the remaining size is less than the min order size.
            OrderValidation.validateOrderSize(
                marketConfig.orderPricingParameters.minOrderSizeUsd,
                marketConfig.orderPricingParameters.maxOrderSizeUsd,
                order.numbers.sizeDeltaUsd
            );
        }

        // Validate the position size.
        // The position size must be within the min/max bounds.
        // The position size is the open interest and not the current size.
        OrderValidation.validatePositionSize(
            marketConfig.positionParameters.minPositionSizeUsd,
            marketConfig.positionParameters.maxPositionSizeUsd,
            result.positionSizeNextUsd
        );

        // Set the order type depending on whether or not it is a limit order.
        order.orderType = IGmxV2OrderTypes.OrderType.MarketDecrease;

        // Make sure the PnL / Collateral swap is set to swap to USDC.
        order.decreasePositionSwapType = IGmxV2OrderTypes
            .DecreasePositionSwapType
            .SwapPnlTokenToCollateralToken;

        // Set the initial order values that are the same for every order.
        order.referralCode = marketConfig.sharedOrderParameters.referralCode;

        order.addresses = OrderHelpers.createOrderAddresses(
            market,
            marketInfo.longToken,
            marketConfig.sharedOrderParameters.uiFeeReceiver,
            true
        );

        // Set the callback gas limit and execution fee for the order.
        order.numbers.callbackGasLimit = marketConfig
            .sharedOrderParameters
            .callbackGasLimit;
        order.numbers.executionFee = executionFee;

        OrderValidation.validateExecutionFee(
            dataStore,
            order.orderType,
            order.addresses.swapPath.length,
            order.numbers.callbackGasLimit,
            marketConfig.sharedOrderParameters.executionFeeBufferPercent,
            tx.gasprice,
            order.numbers.executionFee
        );

        return (
            order,
            sendOrder(manager, executionFeeRecipients_, order, executionFee)
        );
    }

    /**
     * @notice Cancels the order with `orderKey = key`. Liquidation orders can only be cancelled if they have not been executed after the `liquidationOrderTimeoutDeadline`.
     * Liquidators can always cancel non-liquidation orders (orders created by the account owner).
     * @param manager              The configuration manager for the strategy.
     * @param pendingLiquidations_ A storage pointer to the pending liquidations mapping.
     * @param key                  The order key of the order that should be cancelled.
     */
    function cancelOrder(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => PendingLiquidation) storage pendingLiquidations_,
        bytes32 key
    ) external {
        if (pendingLiquidations_[key].feeRecipient != address(0)) {
            require(
                block.timestamp >
                    pendingLiquidations_[key].orderTimestamp +
                        manager.getLiquidationOrderTimeoutDeadline(), // 10 mins
                GmxFrfStrategyErrors
                    .ORDER_MANAGEMENT_LIQUIDATION_ORDER_CANNOT_BE_CANCELLED_YET
            );
        }

        manager.gmxV2ExchangeRouter().cancelOrder(key);
    }

    function afterOrderExecution(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => PendingLiquidation) storage pendingLiquidations_,
        bytes32 key,
        IGmxV2OrderTypes.Props memory order,
        IGmxV2EventUtilsTypes.EventLogData memory
    ) external {
        // Since anyone can set this contract as the callback, we need to make sure that
        // the key is valid.
        require(
            order.addresses.account == address(this),
            GmxFrfStrategyErrors.ORDER_MANAGEMENT_ORDER_MUST_BE_FOR_THIS_ACCOUNT
        );

        PendingLiquidation memory pendingLiquidation = pendingLiquidations_[
            key
        ];

        if (pendingLiquidation.feeRecipient != address(0)) {
            _payLiquidationFee(
                manager,
                pendingLiquidation.feeRecipient,
                pendingLiquidation.feesOwedUsd
            );

            delete pendingLiquidations_[key];
        }
    }

    /**
     * @notice Called after an order cancellation.
     * @param pendingLiquidations_ The liquidation orders that were pending and need to be canceled.
     * @param order                The order that was cancelled.
     */
    function afterOrderCancellation(
        mapping(bytes32 => PendingLiquidation) storage pendingLiquidations_,
        bytes32 key,
        IGmxV2OrderTypes.Props memory order,
        IGmxV2EventUtilsTypes.EventLogData memory
    ) external {
        // Since anyone can set this contract as the callback, we need to make sure that
        // the key is valid.
        require(
            order.addresses.account == address(this),
            GmxFrfStrategyErrors.ORDER_MANAGEMENT_ORDER_MUST_BE_FOR_THIS_ACCOUNT
        );

        // If it is a liquidation order that was cancelled, we should clear it.
        delete pendingLiquidations_[key];
    }

    // ============ Private Functions ============

    /**
     * @notice Pay liquidation fee to liquidator, incetivizing liquidations that keep the protocol
     * healthy.
     * @dev If the balance of this contract is less than the fee amount requested, will just
     * send the balance of this contract as the fee.
     * @param manager      The configuration manager for the strategy.
     * @param feeRecipient The address of the recipient of the fee.
     * @param feeAmountUsd The amount of assets transferred to the `feeRicipient`.
     */
    function _payLiquidationFee(
        IGmxFrfStrategyManager manager,
        address feeRecipient,
        uint256 feeAmountUsd
    ) private {
        IERC20 usdc = manager.USDC();

        // Get the USDC balance of this contract.
        uint256 balanceUsdc = usdc.balanceOf(address(this));

        // Get the fee amount in USDC.
        uint256 feeAmountTokens = Pricing.getTokenAmountForUSD(
            manager,
            address(usdc),
            feeAmountUsd
        );

        // Transfer the fee amount if possible or balance of this contract to the recipient.
        usdc.safeTransfer(feeRecipient, Math.min(feeAmountTokens, balanceUsdc));
    }

    /**
     * @notice Sends an order to the GMX exchange router. This function also calls _transferOrderAssets to transfer the collateral to the router.
     * @param manager                 The configuration manager for the strategy.
     * @param executionFeeRecipients_ The storage pointer to the executionFeeRecipients mapping.
     * @param order                   The order to send.
     * @param executionFee            The gas stipend for executing the transfer.
     * @return orderKey               The key of the order that was sent.
     */
    function sendOrder(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => address) storage executionFeeRecipients_,
        IGmxV2OrderTypes.CreateOrderParams memory order,
        uint256 executionFee
    ) private returns (bytes32 orderKey) {
        uint256 collateralToSend = 0;

        if (order.orderType != IGmxV2OrderTypes.OrderType.MarketDecrease) {
            collateralToSend = order.numbers.initialCollateralDeltaAmount;
        }

        // Transfer the collateral (if applicable) + the execution fee.
        transferOrderAssets(
            IERC20(order.addresses.initialCollateralToken),
            manager.WRAPPED_NATIVE_TOKEN(),
            collateralToSend,
            executionFee,
            manager.gmxV2OrderVault()
        );

        orderKey = manager.gmxV2ExchangeRouter().createOrder(order);

        executionFeeRecipients_[orderKey] = msg.sender;

        return orderKey;
    }

    /**
     * @notice Transfers the collateral and the execution fee to the GMX order vault.
     * @param initialCollateralToken The token that the collateral is in.
     * @param wrappedNativeToken     The wrapped native token.
     * @param collateralTokenAmount  The amount of collateral to send.
     * @param executionFee           The gas stipend for executing the transfer.
     * @param gmxV2OrderVault        The address of the GMX order vault.
     */
    function transferOrderAssets(
        IERC20 initialCollateralToken,
        IWrappedNativeToken wrappedNativeToken,
        uint256 collateralTokenAmount,
        uint256 executionFee,
        address gmxV2OrderVault
    ) private {
        // Send wrapped native to GMX order vault. This amount can be just the gas stipend, or the
        // gas stipend + the amount of collateral we want to send to the GMX order vault.
        if (executionFee != 0) {
            // Wrap the native token.
            wrappedNativeToken.deposit{ value: executionFee }();
            // Transfer the wrapped native token to the GMX order vault.
            wrappedNativeToken.safeTransfer(gmxV2OrderVault, executionFee);
        }

        // Don't need to do anything if it is zero.
        if (collateralTokenAmount != 0) {
            // Transfer the collateral token to the GMX order vault.
            initialCollateralToken.safeTransfer(
                gmxV2OrderVault,
                collateralTokenAmount
            );
        }

        // It is important to note that, after this function is called, a method that triggers the `recordTransferIn` method on the
        // GmxV2ExchangeRouter MUST be called, otherwise funds will be lost. GMX accounts the assets in the exchange router assuming they were zero at the beggining of
        // the transaction, so if a method that calls `recordTransferIn` is not called after assets are transferred, GMX will not revert and there is no way
        // to recover these assets.
    }
}

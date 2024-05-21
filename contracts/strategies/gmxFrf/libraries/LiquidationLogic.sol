// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IGmxFrfStrategyManager
} from "../interfaces/IGmxFrfStrategyManager.sol";
import { GmxStorageGetters } from "./GmxStorageGetters.sol";
import { GmxMarketGetters } from "./GmxMarketGetters.sol";
import {
    IChainlinkAdapter
} from "../../../adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import { IGmxV2DataStore } from "../interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2OrderTypes
} from "../../../lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import {
    PositionStoreUtils
} from "../../../lib/gmx/position/PositionStoreUtils.sol";
import { Pricing } from "./Pricing.sol";
import {
    IGmxV2PositionTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";
import { IMarketConfiguration } from "../interfaces/IMarketConfiguration.sol";
import { Constants } from "../../../libraries/Constants.sol";
import { PercentMath } from "../../../libraries/PercentMath.sol";
import { OrderStoreUtils } from "../../../lib/gmx/order/OrderStoreUtils.sol";
import { GmxFrfStrategyErrors } from "../GmxFrfStrategyErrors.sol";
import { OrderValidation } from "./OrderValidation.sol";
import {
    IGmxFrfStrategyAccount
} from "../interfaces/IGmxFrfStrategyAccount.sol";
import { DeltaConvergenceMath } from "./DeltaConvergenceMath.sol";
import { ClaimLogic } from "./ClaimLogic.sol";
import { OrderLogic } from "./OrderLogic.sol";
import { Role } from "../../../lib/gmx/role/Role.sol";
import { SwapCallbackLogic } from "./SwapCallbackLogic.sol";

/**
 * @title LiquidationLogic
 * @author GoldLink
 *
 * @dev Logic for handling the liquidations for the GmxFrf strategy.
 */
library LiquidationLogic {
    using SafeERC20 for IERC20;
    using PercentMath for uint256;

    // ============ External Functions ============

    /**
     * @notice Executes a swap rebalance. This method takes long tokens from the account's balance and claimable funding fees and allows the caller
     * to swap them for USDC, taking a fee in the process. This method can only be called if the account's market delta for the specified market
     * is long. The maximum number of tokens the rebalancer can swap is determined by the difference `longPositionSizeTokens - shortPositionSizeTokens`.
     * This function hands execution off to the provided `callbackContract`, so reentrancy throughout the account must be guarded against exteremely carefully.
     * @param manager              The manager for the strategy.
     * @param pendingLiquidations_ The pending liquidations that will be canceled for the position.
     * @param market               The market to rebalance. This will be used to determine the token to sell.
     * @param callbackConfig       The callback configuration for the liquidation. At least `expectedUSDC` must be returned to the contract, otherwise the call will revert.
     * @return rebalanceAmount     The amount of tokens sent out of the contract to be swapped for USDC.
     * @return usdcAmountIn        The callback configuration for the liquidation. At least `expectedUSDC` must be returned to the contract, otherwise the call will revert.
     */
    function swapRebalancePosition(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => OrderLogic.PendingLiquidation)
            storage pendingLiquidations_,
        address market,
        IGmxFrfStrategyAccount.CallbackConfig memory callbackConfig
    ) external returns (uint256 rebalanceAmount, uint256 usdcAmountIn) {
        IGmxV2DataStore dataStore = manager.gmxV2DataStore();

        // Attempt to cancel orders in this market to prepare for the releverage. If this cannot be done, this will revert.
        // In the event that an order is cancelled, but the account is not able to be releveraged,
        // the call will later revert, preserving the order's active status.
        _cancelOrdersForLiquidation(manager, pendingLiquidations_, market);

        // It is not feasible to calculate the delta of a position when an order is currently active, as the output of the order has not yet been determined.
        // Furthermore, since the strategy only allows for market order types, there is not a risk of a limit order blocking a swap rebalance from executing.
        OrderValidation.validateNoPendingOrdersInMarket(dataStore, market);

        // Get the position's breakdown in order to calculate the position's delta. Pass in `useMaxSizeDelta = true` so that the entirety of the position's costs
        // are considered when evaluating the delta.
        DeltaConvergenceMath.PositionTokenBreakdown
            memory breakdown = DeltaConvergenceMath.getAccountMarketDelta(
                manager,
                address(this),
                market,
                0,
                true
            );

        IMarketConfiguration.UnwindParameters memory unwindConfig = manager
            .getMarketUnwindConfiguration(market);

        {
            // Get the delta proportion of the position, which indicates the which direction the position is imbalanced in (i.e. the position is too short or too long),
            // and the proportion of the position's imbalance (i.e. short tokens / long tokens for a short delta, and  long tokens / short tokens for a long delta).
            // The `deltaProportion` is a percentage represented in WAD.
            (uint256 proportion, bool isShort) = DeltaConvergenceMath
                .getDeltaProportion(
                    breakdown.tokensShort,
                    breakdown.tokensLong
                );

            // If a position's delta is too short, it is not possible to rebalance the position with a swap. This is because the short portion of the position
            // is a perpetual on GMX. If a position's delta is short, `_rebalancePosition` should be used instead.
            require(
                proportion >= unwindConfig.maxDeltaProportion && !isShort,
                GmxFrfStrategyErrors
                    .LIQUIDATION_MANAGEMENT_POSITION_DELTA_IS_NOT_SUFFICIENT_FOR_SWAP_REBALANCE
            );
        }

        // Optimistically claim unclaimed funding fees. This simply transfers the owed funding fees from GMX
        // to the account's balance.
        if (breakdown.claimableLongTokens != 0) {
            ClaimLogic.claimFundingFeesInMarket(manager, market);
        }

        address longToken = GmxMarketGetters.getLongToken(
            manager.gmxV2DataStore(),
            market
        );

        {
            uint256 accountBalance = IERC20(longToken).balanceOf(address(this));

            // Max amount to that is allowed for rebalance is `tokensLong - tokensShort`, as this would leave the position with a Delta of 1.0.
            // The swap rebalance amount is also constrained by the atomically available balance of the account.
            // Furthermore, since the rebalancer can provide a maximum amount of tokens to be swapped, the rebalance amount is also constrained by their inputted maximum amount.
            rebalanceAmount = Math.min(
                Math.min(
                    breakdown.tokensLong - breakdown.tokensShort,
                    accountBalance
                ),
                callbackConfig.tokenAmountMax
            );

            uint256 remaining = accountBalance - rebalanceAmount;

            // To prevent gaming and preventing token rebalances by continuously sending tokens to the account, the size of the swap rebalance must either
            // 1) Leave the account with zero delta.
            // 2) Leave the account with zero tokens that can be atomically swapped (i.e., the entirety of this market's long position resides in either unsettled funding fees or position collateral),
            // 3) Leave the account with a balance that is greater than or equal to the minimum swap rebalance size.
            require(
                rebalanceAmount ==
                    breakdown.tokensLong - breakdown.tokensShort ||
                    remaining == 0 ||
                    remaining >= unwindConfig.minSwapRebalanceSize,
                GmxFrfStrategyErrors
                    .LIQUIDATION_MANAGEMENT_REBALANCE_AMOUNT_LEAVE_TOO_LITTLE_REMAINING_ASSETS
            );
        }

        // Call the liquidation callback handler.
        return (
            rebalanceAmount,
            SwapCallbackLogic.handleSwapCallback(
                manager,
                longToken,
                rebalanceAmount,
                manager.getAssetLiquidationFeePercent(longToken),
                callbackConfig.callback,
                callbackConfig.receiever
            )
        );
    }

    /**
     * @notice Rebalances a position by unwinding it. This function allows a liquidator to forcibly unwind a position by either selling collateral if the delta is positive
     * or by decreeasing the short position if negative. The liquidator recieves a fee once the position is unwound.
     * @dev This function can only be called if the position's delta is greater than the `maxDeltaProportion` as defined in the market's unwind configuration.
     * @dev Furthermore, if the `maxDeltaProportion` is positive, this method can only be called if `_swapRebalancePosition` is not possible to execute, i.e.
     * the account holds less than `minSwapRebalanceSize` of the long token.
     * @param manager                 The manager for the strategy.
     * @param executionFeeRecipients_ The addresses that executed each of the partial liquidations and are therefore
     * receiving fees.
     * @param pendingLiquidations_    The pending liquidations that will be canceled for the position.
     * @param market                  The market to rebalance. This will be used to determine the token to sell.
     * @param executionFee            The gas stipend for executing the transfer in the liquidation.
     * @return order                  The liquidation order that was created via GMX.
     * @return orderKey               The key for the order.
     */
    function rebalancePosition(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => address) storage executionFeeRecipients_,
        mapping(bytes32 => OrderLogic.PendingLiquidation)
            storage pendingLiquidations_,
        address market,
        uint256 executionFee
    )
        external
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        )
    {
        // Attempt to cancel orders in this market to prepare for the rebalance. If this cannot be done, this will revert.
        // In the event that an order is cancelled, but the account is not able to be rebalanced,
        // the call will later revert, preserving the order's active status.
        _cancelOrdersForLiquidation(manager, pendingLiquidations_, market);

        IGmxV2DataStore dataStore = manager.gmxV2DataStore();

        // We need to make sure there is no open orders in the market. The reason for this is because active orders prevent the possibility of calculating the exact delta of a position.
        // Furthermore, the possible order types that can be currently active (decrease, increase, add collateral, and rebalance) (not liquidation because you cannot enter this function when the account's status)
        // is in liquidation) all target a delta of 1.0 and therefore will only benefit the unhealthy delta in this market. It is not possible to prevent a position from being rebalanced
        // by continuously creating orders because every order would shift the delta of the position toward neutrality.
        OrderValidation.validateNoPendingOrdersInMarket(dataStore, market);

        DeltaConvergenceMath.PositionTokenBreakdown
            memory breakdown = DeltaConvergenceMath.getAccountMarketDelta(
                manager,
                address(this),
                market,
                0,
                true
            );

        // Cannot rebalance a position if it does not consist of any tokens.
        require(
            breakdown.tokensShort != 0 || breakdown.tokensLong != 0,
            GmxFrfStrategyErrors
                .LIQUIDATION_MANAGEMENT_NO_ASSETS_EXIST_IN_THIS_MARKET_TO_REBALANCE
        );

        // Get the market unwind configuration, which will be used to determine the maximum deviation of the position.
        IMarketConfiguration.UnwindParameters memory unwindConfig = manager
            .getMarketUnwindConfiguration(market);

        // Get the delta proportion of the position, which indicates the which direction the position is imbalanced in (i.e. the position is too short or too long),
        // and the proportion of the position's imbalance (i.e. short tokens / long tokens for a short delta, and  long tokens / short tokens for a long delta). This is represented in WAD.
        (uint256 proportion, bool isShort) = DeltaConvergenceMath
            .getDeltaProportion(breakdown.tokensShort, breakdown.tokensLong);

        // Revert if the positions delta proportion is less than the `maxDeltaProportion` as defined in the market's unwind configuration.
        require(
            proportion >= unwindConfig.maxDeltaProportion,
            GmxFrfStrategyErrors
                .LIQUIDATION_MANAGEMENT_POSITION_IS_WITHIN_MAX_DEVIATION
        );

        if (isShort) {
            // The size to unwind is the percentage of the position that is above the max deviation. This will properly decrease the
            // the resulting size will properly decrease the position's size by enough to bring the position's delta to 1.0.
            uint256 sizeToUnwind;
            {
                // If the proportion is greater than the max delta proportion and the position is short, part or all of the position must be unwound.
                // The `imbalance` that must be made up is the difference between the position's short and long tokens. Since a delta of 1.0 is desired
                // as this implies the position has no directional exposure.
                uint256 imbalance = breakdown.tokensShort -
                    breakdown.tokensLong;

                // The percent to unwind is the percentage of the position's total size that the imbalance represents. We have to pass in an open interest value to the createDecreaseOrder function,
                // so we use this proportion to calculate the `sizeDeltaUsd.`
                uint256 percentToUnwind = imbalance.fractionToPercent(
                    breakdown.tokensShort
                );

                sizeToUnwind = breakdown
                    .positionInfo
                    .position
                    .numbers
                    .sizeInUsd
                    .percentToFraction(percentToUnwind);
            }

            // Increase the size of the unwind to account for the fee that the unwinder is entitled to.
            sizeToUnwind = Math.min(
                sizeToUnwind +
                    sizeToUnwind.percentToFraction(unwindConfig.unwindFee),
                breakdown.positionInfo.position.numbers.sizeInUsd
            );

            // Return the liquidation order and order key.
            return
                _createLiquidationOrder(
                    manager,
                    executionFeeRecipients_,
                    pendingLiquidations_,
                    market,
                    sizeToUnwind,
                    executionFee
                );
        }

        // Need to make sure that the accounts balance is not above the minSwapRebalance size,
        // as the ERC20 tokens owned by the account should be swapped first before modifying the position.
        require(
            breakdown.accountBalanceLongTokens +
                breakdown.claimableLongTokens <=
                unwindConfig.minSwapRebalanceSize,
            GmxFrfStrategyErrors
                .LIQUIDATION_MANAGEMENT_AVAILABLE_TOKEN_BALANCE_MUST_BE_CLEARED_BEFORE_REBALANCING
        );

        // We now know that the only way to rebalance this position is to sell collateral or unsettled funding fees.
        // We can sell collateral and settle funding fees by calling `_createLiquidationOrder` using a sizeDeltaUsd of
        // 0, since this will properly sell excess collateral as well as settle funding fees.

        return
            _createLiquidationOrder(
                manager,
                executionFeeRecipients_,
                pendingLiquidations_,
                market,
                0,
                executionFee
            );
    }

    /**
     * @notice Releverages a position by unwinding it. This function allows a liquidator to close a position in the event the position's leverage is too high.
     * The liquidator recieves a fee once the position is unwound. This function can only be called if the position's leverage is greater than the `maxPositionLeverage`
     * as defined in the market's unwind configuration.
     * @param manager                 The manager for the strategy.
     * @param executionFeeRecipients_ The addresses that executed each of the partial liquidations and are therefore
     * receiving fees.
     * @param pendingLiquidations_    The pending liquidations that will be canceled for the position.
     * @param market                  The market in which's position should be releveraged.
     * @param sizeDeltaUsd            The `sizeDeltaUsd` of the liquidation order. This represents the reduction in the size of the short position on GMX. Must comply with
     * the configured `minOrderSize` and `maxOrderSize`. Furthermore, the position after creating the decrease order must abide by the `minimumPositionSize`.
     * @param executionFee            The gas stipend for executing the transfer in the liquidation.
     * @return order                  The liquidation order that was created via GMX.
     * @return orderKey               The key for the order.
     */
    function releveragePosition(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => address) storage executionFeeRecipients_,
        mapping(bytes32 => OrderLogic.PendingLiquidation)
            storage pendingLiquidations_,
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
        // Attempt to cancel orders in this market to prepare for the releverage. If this cannot be done, this will revert.
        // In the event that an order is cancelled, but the account is not able to be releveraged,
        // the call will later revert, preserving the order's active status.
        _cancelOrdersForLiquidation(manager, pendingLiquidations_, market);

        // Get the position token breakdown for the position in the specified market.
        // Note that `useMaxSizeDelta = true` is passed in, rather than `sizeDeltaUsd`. This is because GMX incorperates the price impact
        // of closing a position when calculating a position's leverage for the purpose of liquidations. Since price impact is dependant on the size of the position,
        // the maximum must be used fairly evaluate the leverage.
        DeltaConvergenceMath.PositionTokenBreakdown
            memory breakdown = DeltaConvergenceMath.getAccountMarketDelta(
                manager,
                address(this),
                market,
                0,
                true
            );

        // The position's leverage must be above the configured `maxPositionLeverage` threshold in order for it
        // to be releveraged. Not to be confused with the position's delta, the leverage of a position is the ratio
        // of the size of the position to the position's remaining collateral. Since the position's remaining is calculated as
        // `remaining collateral = collateral value - unpaid funding fees - borrowing fees + pnlIncludingPriceImpact`.
        // Even though positions are meant to be delta neutral, the leverage of the position can change as the as the position
        // accrues fees and price impact changes.
        IMarketConfiguration.UnwindParameters memory unwindConfig = manager
            .getMarketUnwindConfiguration(market);
        require(
            breakdown.leverage >= unwindConfig.maxPositionLeverage,
            GmxFrfStrategyErrors
                .LIQUIDATION_MANAGEMENT_POSITION_IS_WITHIN_MAX_LEVERAGE
        );

        return
            _createLiquidationOrder(
                manager,
                executionFeeRecipients_,
                pendingLiquidations_,
                market,
                sizeDeltaUsd,
                executionFee
            );
    }

    // ============ Public Functions ============

    /**
     * @notice Liquidate a position, canceling orders for the market and then creating a liquidation order.
     * @param manager                 The manager for the strategy.
     * @param executionFeeRecipients_ The addresses that executed each of the partial liquidations and are therefore
     * receiving fees.
     * @param pendingLiquidations_    The pending liquidations that will be canceled for the position.
     * @param market                  The market in which's position should be releveraged.
     * @param sizeDeltaUsd            The `sizeDeltaUsd` of the liquidation order. This represents the reduction in the size of the short position on GMX. Must comply with
     * the configured `minOrderSize` and `maxOrderSize`. Furthermore, the position after creating the decrease order must abide by the `minimumPositionSize`.
     * @param executionFee            The gas stipend for executing the transfer in the liquidation.
     * @return order                  The liquidation order that was created via GMX.
     * @return orderKey               The key for the order.
     */
    function liquidatePosition(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => address) storage executionFeeRecipients_,
        mapping(bytes32 => OrderLogic.PendingLiquidation)
            storage pendingLiquidations_,
        address market,
        uint256 sizeDeltaUsd,
        uint256 executionFee
    )
        public
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        )
    {
        // Attempt to cancel orders in this market to prepare for the liquidaation. If this cannot be done, this will revert.
        // In the event that an order is cancelled, but the account is not able to be liqidated,
        // the call will later revert, preserving the order's active status.
        _cancelOrdersForLiquidation(manager, pendingLiquidations_, market);

        // Create & return the liquidation order.
        return
            _createLiquidationOrder(
                manager,
                executionFeeRecipients_,
                pendingLiquidations_,
                market,
                sizeDeltaUsd,
                executionFee
            );
    }

    // ============ Private Functions ============

    /**
     * @notice Create a liquidation order for the purposes of unwinding a position. Called by methods that allow a third party to forcibly modify an order,
     * which consist of `executeLiquidatePosition`, `executeReleveragePosition`, and `executeRebalancePosition`.
     * @param manager                 The manager for the strategy.
     * @param executionFeeRecipients_ The addresses that executed each of the partial liquidations and are therefore
     * receiving fees.
     * @param pendingLiquidations_    The pending liquidations that will be canceled for the position.
     * @param market                  The market in which's position should be releveraged.
     * @param sizeDeltaUsd            The `sizeDeltaUsd` of the liquidation order. This represents the reduction in the size of the short position on GMX. Must comply with
     * the configured `minOrderSize` and `maxOrderSize`. Furthermore, the position after creating the decrease order must abide by the `minimumPositionSize`.
     * @param executionFee            The gas stipend for executing the transfer in the liquidation.
     * @return order                  The liquidation order that was created via GMX.
     * @return orderKey               The key for the order.
     */
    function _createLiquidationOrder(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => address) storage executionFeeRecipients_,
        mapping(bytes32 => OrderLogic.PendingLiquidation)
            storage pendingLiquidations_,
        address market,
        uint256 sizeDeltaUsd,
        uint256 executionFee
    )
        private
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        )
    {
        // Since `_createDecreaseOrder` handles all delta calculations, creating a liquidation order just consists of creating a liquidation order
        // and saving the fees owed to the liquidator and the timestamp that the order was created.
        (order, orderKey) = OrderLogic.createDecreaseOrder(
            manager,
            executionFeeRecipients_,
            market,
            sizeDeltaUsd,
            executionFee
        );

        // Get the fee amount that should be paid to the liquidator. This will be used to pay the liquidator once the order has been executed.
        // The fee amount is solely based on the output amount of the order.
        IMarketConfiguration.UnwindParameters memory unwindConfig = manager
            .getMarketUnwindConfiguration(market);
        uint256 feeAmountUsd = order.numbers.minOutputAmount.percentToFraction(
            unwindConfig.unwindFee
        );

        // Add the pending liquidation to storage mapping of all pending liquidations.
        pendingLiquidations_[orderKey] = OrderLogic.PendingLiquidation({
            feesOwedUsd: feeAmountUsd,
            feeRecipient: msg.sender,
            // Intentionally casting without SafeCast because the timestamp cannot overflow uint64.
            orderTimestamp: uint64(block.timestamp)
        });

        return (order, orderKey);
    }

    /**
     * @notice Cancel orders for liquidation. Additionally, if there is currently an order in the market, try to cancel it.
     * @param manager               The manager for the strategy.
     * @param pendingLiquidations_  The pending liquidations that will be canceled for the position.
     * @param market                The market in which the liquidation is being done.
     */
    function _cancelOrdersForLiquidation(
        IGmxFrfStrategyManager manager,
        mapping(bytes32 => OrderLogic.PendingLiquidation)
            storage pendingLiquidations_,
        address market
    ) private {
        // Get the current orderKey in the market, if any.
        (, bytes32 pendingOrderKey) = OrderStoreUtils.getOrderInMarket(
            manager.gmxV2DataStore(),
            address(this),
            market
        );

        if (pendingOrderKey != bytes32(0)) {
            // If there is currently an order in the market, try to cancel it. This will attempt to cancel any account owner's order
            // in the event that it exists. Furthermore, it will cancel any liquidation order that has not been executed by a keeper
            // within `liquidationTimeOutDeadline` seconds. If `liquidationTimeoutDeadline` seconds have not passed since the last liquidation order,
            // this call will revert, preventing liquidators from stealing eachother's liquidation. It should be noted that
            // GMX also has a block minimum before a market order can be cancelled, in that case, this call will revert because attempting to call
            // `GmxV2Router.cancelOrder` will revert.

            // Note that this only applies to liquidation orders; rebalance orders will never reach this point as `validateNoPendingOrders` is called
            // in `rebalancePosition` first.
            OrderLogic.cancelOrder(
                manager,
                pendingLiquidations_,
                pendingOrderKey
            );
        }
    }
}

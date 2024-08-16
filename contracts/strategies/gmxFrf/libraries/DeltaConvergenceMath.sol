// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";

import { PercentMath } from "../../../libraries/PercentMath.sol";
import {
    IGmxV2PriceTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2PriceTypes.sol";
import {
    IGmxV2MarketTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2MarketTypes.sol";
import {
    IGmxV2PositionTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";
import {
    PositionStoreUtils
} from "../../../lib/gmx/position/PositionStoreUtils.sol";
import {
    IGmxV2ReferralStorage
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2ReferralStorage.sol";
import {
    IGmxFrfStrategyManager
} from "../interfaces/IGmxFrfStrategyManager.sol";
import {
    GmxStorageGetters
} from "../../../strategies/gmxFrf/libraries/GmxStorageGetters.sol";
import {
    GmxMarketGetters
} from "../../../strategies/gmxFrf/libraries/GmxMarketGetters.sol";
import { Pricing } from "./Pricing.sol";
import { Constants } from "../../../libraries/Constants.sol";

/**
 * @title DeltaConvergenceMath
 * @author GoldLink
 *
 * @dev Math and checks library for validating position delta.
 */
library DeltaConvergenceMath {
    using PercentMath for uint256;

    // ============ Structs ============

    struct DeltaCalculationParameters {
        address marketAddress;
        address account;
        uint256 shortTokenPrice;
        uint256 longTokenPrice;
        address uiFeeReceiver;
        IGmxV2MarketTypes.Props market;
    }

    struct DecreasePositionResult {
        uint256 sizeDeltaActualUsd;
        uint256 positionSizeNextUsd;
        uint256 estimatedOutputUsd;
        uint256 collateralToRemove;
        uint256 executionPrice;
    }

    struct IncreasePositionResult {
        uint256 sizeDeltaUsd;
        uint256 executionPrice;
        uint256 positionSizeNextUsd;
        uint256 swapOutputTokens;
        uint256 swapOutputMarkedToMarket;
    }

    struct PositionTokenBreakdown {
        uint256 tokensShort;
        uint256 tokensLong;
        uint256 accountBalanceLongTokens;
        uint256 claimableLongTokens;
        uint256 unsettledLongTokens;
        uint256 collateralLongTokens;
        uint256 fundingAndBorrowFeesLongTokens;
        uint256 leverage;
        IGmxV2PositionTypes.PositionInfo positionInfo;
    }

    // ============ Internal Functions ============

    /**
     * @notice Get the value of a position in terms of USD. The `valueUSD` reflects the value that could be extracted from the position if it were liquidated right away,
     * and thus accounts for the price impact of closing the position.
     * @param manager    The manager that controls the strategy and maintains configuration state.
     * @param account    The account to get the position value for.
     * @param market     The market the position is for.
     * @return valueUSD  The expected value of the position after closing the position given at the current market prices and GMX pool state.
     */
    function getPositionValueUSD(
        IGmxFrfStrategyManager manager,
        address account,
        address market
    ) internal view returns (uint256 valueUSD) {
        // The value of a position is made up of the following fields:
        // 1. The value of the collateral.
        // 2. The value of unsettled positive funding fees, which consist of both shortTokens and longTokens.
        // 3. The loss of value due to borrowing fees and negative fees, which consist strictly of the `collateralToken.` At the time of decreasing the position, this value is offset by profit if possible,
        // however, this is not accounted for in the PnL.
        // 4. The PnL, which is a signed integer representing the profit or loss of the position.
        // 5. The loss due to the price impact of closing the position, which is ultimately included in the `positionPnlIncludingPriceImpactUsd` field.
        // 6. The loss due to the price impact of swapping the collateral token into USDC.

        // It is important to also not the values that may be related to the position but are not included in the value of the position.
        // 1. The unclaimed, settled funding fees are not included in the value of a position because, once settled, they are inherently seperate and can be atomically claimed.
        //    Furthermore, they are not "locked" in the position and can be though of as an auxiliary token balance.
        // 2. The value of the ERC20 tokens in the account. These do not relate to the position that is held on GMX and therefore are factored into the value of the account separately.

        // Passing true for `useMaxSizeDelta` because the cost of exiting the entire positon must be considered
        // (due to price impact and fees) in order properly account the estimated value.
        IGmxV2PositionTypes.PositionInfo memory positionInfo = getPositionInfo(
            manager,
            account,
            market,
            0,
            true
        );

        // Get information on the position's market to discern prices.
        IGmxV2MarketTypes.Props memory marketInfo = GmxMarketGetters.getMarket(
            manager.gmxV2DataStore(),
            market
        );

        // Get the prices for the market tokens.
        IGmxV2MarketTypes.MarketPrices memory prices;
        {
            uint256 shortTokenPrice = Pricing.getUnitTokenPriceUSD(
                manager,
                marketInfo.shortToken
            );

            uint256 longTokenPrice = Pricing.getUnitTokenPriceUSD(
                manager,
                marketInfo.longToken
            );

            prices = _makeMarketPrices(shortTokenPrice, longTokenPrice);
        }

        // Get the decrease output. This is the expected decrease amount out.
        uint256 decreaseOutputUSD;
        {
            // Add the claimable long token amount to the value of the position.
            valueUSD += Pricing.getTokenValueUSD(
                positionInfo.fees.funding.claimableLongTokenAmount,
                prices.longTokenPrice.max
            );

            uint256 collateralOutputTokens;
            {
                // Get the collateral cost and output in long token. One of these values will be zero.
                (
                    uint256 collateralCostTokens,
                    uint256 outputTokens
                ) = getDecreaseOrderCostsAndOutput(
                        prices.longTokenPrice.max,
                        positionInfo
                    );

                // The amount of collateral tokens being swapped that contribute to the `outputAmount` of the position decrease. The `collateralAmount` of the position after the decrease should
                // equal the position's `sizeInTokens`.
                collateralOutputTokens =
                    positionInfo.position.numbers.collateralAmount +
                    outputTokens -
                    collateralCostTokens;
            }

            // Get the expected output in USD of the position decrease, which includes both positive PnL and collateral.
            (decreaseOutputUSD, , ) = manager.gmxV2Reader().getSwapAmountOut(
                manager.gmxV2DataStore(),
                marketInfo,
                prices,
                marketInfo.longToken,
                collateralOutputTokens,
                manager.getUiFeeReceiver()
            );
        }

        // Add the claimable short balance + the decrease output to the value of the position.
        valueUSD += Pricing.getTokenValueUSD(
            positionInfo.fees.funding.claimableShortTokenAmount +
                decreaseOutputUSD,
            prices.shortTokenPrice.max
        );

        return valueUSD;
    }

    /**
     * @notice Get the market delta for an account, which gives a breakdown of the position encompassed by `market`.
     * @param manager         The configuration manager for the strategy.
     * @param account         The account to get the market delta for.
     * @param sizeDeltaUsd    The size delta to evaluate based off.
     * @param useMaxSizeDelta Whether to use the max size delta.
     */
    function getAccountMarketDelta(
        IGmxFrfStrategyManager manager,
        address account,
        address market,
        uint256 sizeDeltaUsd,
        bool useMaxSizeDelta
    ) internal view returns (PositionTokenBreakdown memory breakdown) {
        // If the market is not approved, then there is zero delta.
        if (!manager.isApprovedMarket(market)) {
            return breakdown;
        }

        // Get the long token for the market.
        (, address longToken) = GmxMarketGetters.getMarketTokens(
            manager.gmxV2DataStore(),
            market
        );

        breakdown.accountBalanceLongTokens = IERC20(longToken).balanceOf(
            account
        );
        breakdown.tokensLong += breakdown.accountBalanceLongTokens;

        // Claimable funding fees are considered as long tokens.
        breakdown.claimableLongTokens += GmxStorageGetters
            .getClaimableFundingFees(
                manager.gmxV2DataStore(),
                market,
                longToken,
                account
            );
        breakdown.tokensLong += breakdown.claimableLongTokens;

        // Get the position information.
        breakdown.positionInfo = getPositionInfo(
            manager,
            account,
            market,
            sizeDeltaUsd,
            useMaxSizeDelta
        );

        // Position collateral.
        breakdown.collateralLongTokens = breakdown
            .positionInfo
            .position
            .numbers
            .collateralAmount;
        breakdown.tokensLong += breakdown.collateralLongTokens;

        // Unclaimed funding fees.
        breakdown.unsettledLongTokens = breakdown
            .positionInfo
            .fees
            .funding
            .claimableLongTokenAmount;
        breakdown.tokensLong += breakdown.unsettledLongTokens;

        // Position size.
        breakdown.tokensShort = breakdown
            .positionInfo
            .position
            .numbers
            .sizeInTokens;

        breakdown.fundingAndBorrowFeesLongTokens = breakdown
            .positionInfo
            .fees
            .totalCostAmount;
        breakdown.tokensLong -= Math.min(
            breakdown.fundingAndBorrowFeesLongTokens,
            breakdown.tokensLong
        );

        breakdown.leverage = _getLeverage(manager, market, breakdown);

        return breakdown;
    }

    function getIncreaseOrderValues(
        IGmxFrfStrategyManager manager,
        uint256 initialCollateralDeltaAmount,
        DeltaCalculationParameters memory values
    ) internal view returns (IncreasePositionResult memory result) {
        // First we need to see if an active position exists, because `getPositionInfo` will revert if it does not exist.
        IGmxV2MarketTypes.MarketPrices memory prices = _makeMarketPrices(
            values.shortTokenPrice,
            values.longTokenPrice
        );

        // We need to figure out the expected swap output given the initial collateral delta amount.
        (result.swapOutputTokens, , ) = manager.gmxV2Reader().getSwapAmountOut(
            manager.gmxV2DataStore(),
            values.market,
            prices,
            values.market.shortToken,
            initialCollateralDeltaAmount,
            values.uiFeeReceiver
        );

        bytes32 positionKey = PositionStoreUtils.getPositionKey(
            values.account,
            values.marketAddress,
            values.market.longToken,
            false
        );

        // Get position information if one already exists.
        IGmxV2PositionTypes.PositionInfo memory info;

        if (
            PositionStoreUtils.getPositionSizeUsd(
                manager.gmxV2DataStore(),
                positionKey
            ) != 0
        ) {
            info = manager.gmxV2Reader().getPositionInfo(
                manager.gmxV2DataStore(),
                manager.gmxV2ReferralStorage(),
                positionKey,
                prices,
                0,
                values.uiFeeReceiver,
                true
            );
        }

        uint256 collateralAfterSwapTokens = info
            .position
            .numbers
            .collateralAmount +
            result.swapOutputTokens -
            info.fees.totalCostAmount;

        uint256 sizeDeltaEstimate = getIncreaseSizeDelta(
            info.position.numbers.sizeInTokens,
            collateralAfterSwapTokens,
            values.longTokenPrice
        );

        // Estimate the execution price with the estimated size delta.
        IGmxV2PriceTypes.ExecutionPriceResult memory executionPrices = manager
            .gmxV2Reader()
            .getExecutionPrice(
                manager.gmxV2DataStore(),
                values.marketAddress,
                IGmxV2PriceTypes.Props(
                    values.longTokenPrice,
                    values.longTokenPrice
                ),
                info.position.numbers.sizeInUsd,
                info.position.numbers.sizeInTokens,
                int256(sizeDeltaEstimate),
                false
            );

        // Recompute size delta using the execution price.
        result.sizeDeltaUsd = getIncreaseSizeDelta(
            info.position.numbers.sizeInTokens,
            collateralAfterSwapTokens,
            executionPrices.executionPrice
        );

        result.positionSizeNextUsd =
            info.position.numbers.sizeInUsd +
            result.sizeDeltaUsd;

        result.executionPrice = executionPrices.executionPrice;

        result.swapOutputMarkedToMarket = Math.mulDiv(
            initialCollateralDeltaAmount,
            values.shortTokenPrice,
            values.longTokenPrice
        );

        return result;
    }

    function getDecreaseOrderValues(
        IGmxFrfStrategyManager manager,
        uint256 sizeDeltaUsd,
        DeltaCalculationParameters memory values
    ) internal view returns (DecreasePositionResult memory result) {
        // Get the minimum of the requested decrease amount and the actual position size.
        result.sizeDeltaActualUsd = getSizeDeltaActualUsd(
            manager,
            values.account,
            values.marketAddress,
            sizeDeltaUsd
        );

        IGmxV2PositionTypes.PositionInfo memory info = getPositionInfo(
            manager,
            values.account,
            values.marketAddress,
            result.sizeDeltaActualUsd,
            false
        );

        // No underflow because (result.sizeDeltaActualUsd / info.position.numbers.sizeInUsd) <= 1
        uint256 shortSizeAfterTokens = info.position.numbers.sizeInTokens -
            (info.position.numbers.sizeInTokens * result.sizeDeltaActualUsd) /
            info.position.numbers.sizeInUsd;

        // Set the result execution price and long token price
        result.executionPrice = info.executionPriceResult.executionPrice;
        result.positionSizeNextUsd =
            shortSizeAfterTokens *
            values.longTokenPrice;

        // Get the collateral cost and output in long token. One of these values will be zero.
        (
            uint256 collateralCostTokens,
            uint256 outputTokens
        ) = getDecreaseOrderCostsAndOutput(values.longTokenPrice, info);

        if (info.position.numbers.sizeInUsd > result.sizeDeltaActualUsd) {
            // If the `totalCostAmount * longTokenPrice > pnlAfterPriceImpactUsd`,
            // then collateral is used to pay for the difference.
            // The collateral amount used to pay for this cost is calculated as follows:
            // `(pnlAfterPriceImpactUsd - totalCostAmount * longTokenPrice) / longTokenPrice ~= collateral paid` (there are swap fees as well that aren't account for in this equation).
            result.collateralToRemove =
                info.position.numbers.collateralAmount -
                Math.min(
                    shortSizeAfterTokens,
                    info.position.numbers.collateralAmount
                );

            result.collateralToRemove -= Math.min(
                result.collateralToRemove,
                collateralCostTokens
            );

            // Set `collateralCostTokens` to zero since this is already account for in `result.collateralToRemove`.
            collateralCostTokens = 0;

            // If there is no collateral to remove or no output tokens, return early.
            if (result.collateralToRemove == 0 && outputTokens != 0) {
                return result;
            }
        } else {
            // If full decrease, swap all collateral.
            result.collateralToRemove = info.position.numbers.collateralAmount;
        }

        // The expected output of the position action accounts for:
        // 1) The positions PnL
        // 2) The negative funding fees of the position, which are first paid out from positive PnL,
        // and then collateral if the PnL does not cover them
        // 3) The collateral being removed to keep the position hedged.

        // All decrease actions target a leverage, of 1.0, not a delta of 1.0.
        // This implies they do not take into account the balance of tokens of the account
        // and / or the unclaimed/unsettled funding fees.
        // In the event the accounts position is rebalancable, this action should be done swiftly.
        // The reason for this is that if an account has a large token balance,
        // it can result in a higher leveraged position if this was accounted for when deciding how to adjust a position's collateral.
        // This must be avoided, and therefore, for any position action, the leverage of the position should converge to 0.

        (uint256 expectedSwapOutput, , ) = manager
            .gmxV2Reader()
            .getSwapAmountOut(
                manager.gmxV2DataStore(),
                values.market,
                _makeMarketPrices(
                    values.shortTokenPrice,
                    values.longTokenPrice
                ),
                values.market.longToken,
                result.collateralToRemove + outputTokens - collateralCostTokens,
                values.uiFeeReceiver
            );

        result.estimatedOutputUsd = expectedSwapOutput * values.shortTokenPrice;

        return result;
    }

    function getDecreaseOrderCostsAndOutput(
        uint256 longTokenPrice,
        IGmxV2PositionTypes.PositionInfo memory info
    ) internal pure returns (uint256 collateralCost, uint256 outputAmount) {
        uint256 collateralCostUSD = info
            .executionPriceResult
            .priceImpactDiffUsd;

        // Increase collateral cost by the total fees.
        collateralCostUSD += info.fees.totalCostAmount * longTokenPrice;

        uint256 outputUSD;
        if (info.executionPriceResult.priceImpactUsd < 0) {
            // If price impact is negative, add impact to collateral cost.
            collateralCostUSD += uint256(
                -info.executionPriceResult.priceImpactUsd
            );
        } else {
            // If price impact is positive, increase output usd by price impact.
            outputUSD += uint256(info.executionPriceResult.priceImpactUsd);
        }

        if (info.basePnlUsd < 0) {
            // If PNL is negative, add to collateral cost.
            collateralCostUSD += uint256(-info.basePnlUsd);
        } else {
            // If PNL is positive, add it to output USD.
            outputUSD += uint256(info.basePnlUsd);
        }

        if (collateralCostUSD > outputUSD) {
            // If collateral cost exceeds output, offset collateral cost by output.
            collateralCostUSD -= outputUSD;
            outputUSD = 0;
        } else {
            // If output exceeds collateral cost, offset output by collateral cost.
            outputUSD -= collateralCostUSD;
            collateralCostUSD = 0;
        }

        // Return both collateral cost and output in long tokens.
        return (collateralCostUSD / longTokenPrice, outputUSD / longTokenPrice);
    }

    /**
     * @notice Get prices of a short and long token.
     * @param manager          The IGmxFrfStrategyManager of the strategy.
     * @param shortToken       The short token whose price is being queried.
     * @param longToken        The long token whose price is being queried.
     * @return shortTokenPrice The price of the short token.
     * @return longTokenPrice  The price of the long token.
     */
    function getMarketPrices(
        IGmxFrfStrategyManager manager,
        address shortToken,
        address longToken
    ) internal view returns (uint256 shortTokenPrice, uint256 longTokenPrice) {
        shortTokenPrice = Pricing.getUnitTokenPriceUSD(manager, shortToken);

        longTokenPrice = Pricing.getUnitTokenPriceUSD(manager, longToken);

        return (shortTokenPrice, longTokenPrice);
    }

    function getIncreaseSizeDelta(
        uint256 currentShortPositionSizeTokens,
        uint256 collateralAfterSwapTokens,
        uint256 executionPrice
    ) internal pure returns (uint256) {
        if (collateralAfterSwapTokens < currentShortPositionSizeTokens) {
            return 0;
        }

        uint256 diff = collateralAfterSwapTokens -
            currentShortPositionSizeTokens;

        return diff * executionPrice;
    }

    /**
     * @notice Get delta proportion, the proportion of the position that is directional.
     * @param shortPositionSizeTokens The size of the short position.
     * @param longPositionSizeTokens  The size of the long position.
     * @return proportion             The proportion of the position that is directional.
     * @return isShort                If the direction is short.
     */
    function getDeltaProportion(
        uint256 shortPositionSizeTokens,
        uint256 longPositionSizeTokens
    ) internal pure returns (uint256 proportion, bool isShort) {
        // Get the direction of the position.
        isShort = shortPositionSizeTokens > longPositionSizeTokens;

        // Max sure the denominator is not 0. If this is the case,
        // then the delta proportion is the maximum that it can be in the direction of the numerator,
        // as the position is completely unhedged on the opposing side.
        if (
            (isShort && longPositionSizeTokens == 0) ||
            (!isShort && shortPositionSizeTokens == 0)
        ) {
            // If both the long position size and the short position size are 0,
            // then the position is perfectly hedged.
            if (longPositionSizeTokens == shortPositionSizeTokens) {
                return (Constants.ONE_HUNDRED_PERCENT, false);
            }

            // Otherwise, the position is unhedged in the direction of the non-zero value,
            // so return a max uint256 to denote this.
            return (type(uint256).max, isShort);
        }

        // Get the proportion of the position that is directional.
        proportion = (isShort)
            ? shortPositionSizeTokens.fractionToPercent(longPositionSizeTokens)
            : longPositionSizeTokens.fractionToPercent(shortPositionSizeTokens);
    }

    // ============ Private Functions ============

    function _getLeverage(
        IGmxFrfStrategyManager manager,
        address market,
        PositionTokenBreakdown memory breakdown
    ) private view returns (uint256 leverage) {
        if (breakdown.positionInfo.position.numbers.sizeInUsd == 0) {
            // Position with 0 size has 0 leverage.
            return 0;
        }

        // The important part here is the position info, not the tokens held in the account. The leverage of the position as GMX sees it is as follows:
        // Short Position Size: Fixed number in terms of USD representing the size of the short. This only changes when you increase or decrease the size, and is not affected by changes in price.
        // Collateral in tokens is gotten by fetching the position `collateralAmount` and subtracting the `totalCostAmount` from that.

        uint256 collateralInTokens = breakdown
            .positionInfo
            .position
            .numbers
            .collateralAmount - breakdown.positionInfo.fees.totalCostAmount;

        uint256 longTokenPrice = Pricing.getUnitTokenPriceUSD(
            manager,
            GmxMarketGetters.getLongToken(manager.gmxV2DataStore(), market)
        );

        // Only negative price impact contributes to the collateral value, positive price impact is not considered when a position is being liquidated.
        if (breakdown.positionInfo.executionPriceResult.priceImpactUsd < 0) {
            collateralInTokens -=
                uint256(
                    -breakdown.positionInfo.executionPriceResult.priceImpactUsd
                ) /
                longTokenPrice;
        }

        // The absolute value of the pnl in tokens.
        uint256 absPnlTokens = SignedMath.abs(
            breakdown.positionInfo.basePnlUsd
        ) / longTokenPrice;

        if (breakdown.positionInfo.basePnlUsd < 0) {
            collateralInTokens -= Math.min(absPnlTokens, collateralInTokens);
        } else {
            collateralInTokens += absPnlTokens;
        }

        if (collateralInTokens == 0) {
            return type(uint256).max;
        }

        // Make sure to convert collateral tokens back to USD.
        leverage = breakdown
            .positionInfo
            .position
            .numbers
            .sizeInUsd
            .fractionToPercent(collateralInTokens * longTokenPrice);

        return leverage;
    }

    function _makeMarketPrices(
        uint256 shortTokenPrice,
        uint256 longTokenPrice
    ) private pure returns (IGmxV2MarketTypes.MarketPrices memory) {
        return
            IGmxV2MarketTypes.MarketPrices(
                IGmxV2PriceTypes.Props(longTokenPrice, longTokenPrice),
                IGmxV2PriceTypes.Props(longTokenPrice, longTokenPrice),
                IGmxV2PriceTypes.Props(shortTokenPrice, shortTokenPrice)
            );
    }

    function _makeMarketPrices(
        IGmxFrfStrategyManager manager,
        address shortToken,
        address longToken
    ) private view returns (IGmxV2MarketTypes.MarketPrices memory) {
        (uint256 shortTokenPrice, uint256 longTokenPrice) = getMarketPrices(
            manager,
            shortToken,
            longToken
        );

        return _makeMarketPrices(shortTokenPrice, longTokenPrice);
    }

    function getPositionInfo(
        IGmxFrfStrategyManager manager,
        address account,
        address market,
        uint256 sizeDeltaUsd,
        bool useMaxSizeDelta
    ) internal view returns (IGmxV2PositionTypes.PositionInfo memory position) {
        (address shortToken, address longToken) = GmxMarketGetters
            .getMarketTokens(manager.gmxV2DataStore(), market);

        // Key is just the hash of the account, market, collateral token and a boolean representing whether or not the position is long.
        // Since the strategy only allows short positions, the position is always short and thus we pass in false to get the position key.
        // Furthermore, since a short position can only be hedged properly with the long token of a market, which the strategy enforces,
        // the long token is always the collateral token.
        bytes32 positionKey = PositionStoreUtils.getPositionKey(
            account,
            market,
            longToken,
            false
        );

        // If no position exists, then there are no values to consider. Furthermore, this prevents `Reader.getPositionInfo` from reverting.
        if (
            PositionStoreUtils.getPositionSizeUsd(
                manager.gmxV2DataStore(),
                positionKey
            ) == 0
        ) {
            return position;
        }

        position = manager.gmxV2Reader().getPositionInfo(
            manager.gmxV2DataStore(),
            manager.gmxV2ReferralStorage(),
            positionKey,
            _makeMarketPrices(manager, shortToken, longToken),
            sizeDeltaUsd,
            manager.getUiFeeReceiver(),
            useMaxSizeDelta
        );

        return position;
    }

    function getSizeDeltaActualUsd(
        IGmxFrfStrategyManager manager,
        address account,
        address market,
        uint256 sizeDeltaRequested
    ) internal view returns (uint256 sizeDeltaActual) {
        // Get the current size of the position.
        uint256 currPositionSizeUSD = getPositionSizeUSD(
            manager,
            account,
            market
        );

        // Return the minimum of the requested size delta or the position size.
        return
            (currPositionSizeUSD < sizeDeltaRequested)
                ? currPositionSizeUSD
                : sizeDeltaRequested;
    }

    function getPositionSizeUSD(
        IGmxFrfStrategyManager manager,
        address account,
        address market
    ) internal view returns (uint256 positionSizeUSD) {
        (, address longToken) = GmxMarketGetters.getMarketTokens(
            manager.gmxV2DataStore(),
            market
        );

        bytes32 positionKey = PositionStoreUtils.getPositionKey(
            account,
            market,
            longToken,
            false
        );

        return
            PositionStoreUtils.getPositionSizeUsd(
                manager.gmxV2DataStore(),
                positionKey
            );
    }
}

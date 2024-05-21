// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";

import { PercentMath } from "../../../libraries/PercentMath.sol";
import {
    IGmxV2DataStore
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2Reader
} from "../../../lib/gmx/interfaces/external/IGmxV2Reader.sol";
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
    PositionStoreUtils
} from "../../../lib/gmx/position/PositionStoreUtils.sol";
import {
    IGmxFrfStrategyManager
} from "../interfaces/IGmxFrfStrategyManager.sol";
import {
    GmxStorageGetters
} from "../../../strategies/gmxFrf/libraries/GmxStorageGetters.sol";
import {
    GmxMarketGetters
} from "../../../strategies/gmxFrf/libraries/GmxMarketGetters.sol";
import { IMarketConfiguration } from "../interfaces/IMarketConfiguration.sol";
import { Pricing } from "./Pricing.sol";

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
        // Passing true for `useMaxSizeDelta` because the cost of exiting the entire positon must be considered
        // (due to price impact and fees) in order properly account the estimated value.
        IGmxV2PositionTypes.PositionInfo memory positionInfo = _getPositionInfo(
            manager,
            account,
            market,
            0,
            true
        );

        (address shortToken, address longToken) = GmxMarketGetters
            .getMarketTokens(manager.gmxV2DataStore(), market);

        uint256 shortTokenPrice = Pricing.getUnitTokenPriceUSD(
            manager,
            shortToken
        );

        uint256 longTokenPrice = Pricing.getUnitTokenPriceUSD(
            manager,
            longToken
        );

        return
            getPositionValueUSD(positionInfo, shortTokenPrice, longTokenPrice);
    }

    /**
     * @notice Get the value of a position in terms of USD. The `valueUSD` reflects the value that could be extracted from the position if it were liquidated right away,
     * and thus accounts for the price impact of closing the position.
     * @param positionInfo    The position information, which is queried from GMX via the `Reader.getPositionInfo` function.
     * @param shortTokenPrice The price of the short token.
     * @param longTokenPrice  The price of the long token.
     * @return valueUSD       The expected value of the position after closing the position given at the current market prices and GMX pool state. This value can only be considered an estimate,
     * as asset prices can change in between the time the value is calculated and when the GMX keeper actually executes the order. Furthermore, price impact can change during this period,
     * as other state changing actions can effect the GMX pool, resulting in a different price impact values.
     */
    function getPositionValueUSD(
        IGmxV2PositionTypes.PositionInfo memory positionInfo,
        uint256 shortTokenPrice,
        uint256 longTokenPrice
    ) internal pure returns (uint256 valueUSD) {
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

        // This accounts for the value of the unsettled short token funding fees.
        valueUSD += Pricing.getTokenValueUSD(
            positionInfo.fees.funding.claimableShortTokenAmount,
            shortTokenPrice
        );

        // The amount of collateral tokens initially held in the position, before accounting for fees, is just the collateral token amount plus the unclaimed funding fees.
        // These are all measured in terms of the longToken of the GMX market, which is also always the token that Goldlink uses to collateralize the position.
        uint256 collateralTokenHeldInPosition = positionInfo
            .position
            .numbers
            .collateralAmount +
            positionInfo.fees.funding.claimableLongTokenAmount;

        // The cost is measured in terms of the collateral token, which includes the GMX borrowing fees and negative funding fees.
        // Therefore, subtract the cost from the collateral tokens to recieve the net amount of collateral tokens held in the position.
        collateralTokenHeldInPosition -= Math.min(
            collateralTokenHeldInPosition,
            positionInfo.fees.totalCostAmount
        );

        // This accounts for the value of the collateral, the unsettled long token funding fees, the negative funding fee amount, the borrowing fees, the UI fee,
        // and the positive impact of the referral bonus.
        valueUSD += Pricing.getTokenValueUSD(
            collateralTokenHeldInPosition,
            longTokenPrice
        );

        // The absolute value of the pnl in terms of USD. This also includes the price impact of closing the position,
        // which can either increase or decrease the value of the position. It is important to include the price impact because for large positions,
        // liquidation may result in high slippage, which can result in the loss of lender funds. In order to trigger liquidations for these positions early, including the price impact
        // in the calculation of the position value is necessary.
        uint256 absPnlAfterPriceImpactUSD = SignedMath.abs(
            positionInfo.pnlAfterPriceImpactUsd
        );

        return
            (positionInfo.pnlAfterPriceImpactUsd < 0)
                ? valueUSD - Math.min(absPnlAfterPriceImpactUSD, valueUSD)
                : valueUSD + absPnlAfterPriceImpactUSD;
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
        breakdown.positionInfo = _getPositionInfo(
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
            .fundingFeeAmount;
        breakdown.tokensLong += breakdown.unsettledLongTokens;

        // Position size.
        breakdown.tokensShort += breakdown
            .positionInfo
            .position
            .numbers
            .sizeInTokens;

        breakdown.fundingAndBorrowFeesLongTokens =
            breakdown.positionInfo.fees.funding.fundingFeeAmount +
            breakdown.positionInfo.fees.borrowing.borrowingFeeAmount;

        // This should not normally happen, but it can in the event that someone checks for the delta
        // of a position before a GMX keeper liquidates the underwater position.

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
            info.fees.funding.fundingFeeAmount -
            info.fees.borrowing.borrowingFeeAmount;

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
        PositionTokenBreakdown memory breakdown = getAccountMarketDelta(
            manager,
            values.account,
            values.marketAddress,
            sizeDeltaUsd,
            false
        );

        // The total cost amount is equal to the sum of the fees associated with the decrease, in terms of the collateral token.
        // This accounts for negative funding fees, borrowing fees,
        uint256 collateralLostInDecrease = breakdown
            .positionInfo
            .fees
            .totalCostAmount;

        {
            uint256 profitInCollateralToken = SignedMath.abs(
                breakdown.positionInfo.pnlAfterPriceImpactUsd
            ) / values.longTokenPrice;

            if (breakdown.positionInfo.pnlAfterPriceImpactUsd > 0) {
                collateralLostInDecrease -= Math.min(
                    collateralLostInDecrease,
                    profitInCollateralToken
                ); // Offset the loss in collateral with position profits.
            } else {
                collateralLostInDecrease += profitInCollateralToken; // adding because this variable is meant to represent a net loss in collateral.
            }
        }

        uint256 sizeDeltaActual = Math.min(
            sizeDeltaUsd,
            breakdown.positionInfo.position.numbers.sizeInUsd
        );

        result.positionSizeNextUsd =
            breakdown.positionInfo.position.numbers.sizeInUsd -
            sizeDeltaActual;

        uint256 shortTokensAfterDecrease;

        {
            uint256 proportionalDecrease = sizeDeltaActual.fractionToPercent(
                breakdown.positionInfo.position.numbers.sizeInUsd
            );

            shortTokensAfterDecrease =
                breakdown.tokensShort -
                breakdown
                    .positionInfo
                    .position
                    .numbers
                    .sizeInTokens
                    .percentToFraction(proportionalDecrease);
        }

        uint256 longTokensAfterDecrease = breakdown.tokensLong -
            collateralLostInDecrease;

        // This is the difference in long vs short tokens currently.
        uint256 imbalance = Math.max(
            shortTokensAfterDecrease,
            longTokensAfterDecrease
        ) - Math.min(shortTokensAfterDecrease, longTokensAfterDecrease);

        if (shortTokensAfterDecrease < longTokensAfterDecrease) {
            // We need to remove long tokens equivalent to the imbalance to make the position delta neutral.
            // However, it is possible that there are a significant number of long tokens in the contract that are impacting the imbalance.
            // If this is the case, then if we were to simply remove the imbalance, it can result in a position with very high leverage. Therefore, we will simply remove
            // the minimum of `collateralAmount - collateralLostInDecrease` the difference in the longCollateral and shortTokens. The rest of the delta imbalance can be left to rebalancers.
            uint256 remainingCollateral = breakdown
                .positionInfo
                .position
                .numbers
                .collateralAmount - collateralLostInDecrease;

            if (remainingCollateral > shortTokensAfterDecrease) {
                result.collateralToRemove = Math.min(
                    remainingCollateral - shortTokensAfterDecrease,
                    imbalance
                );
            }
        }

        if (result.collateralToRemove != 0) {
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
                    result.collateralToRemove,
                    values.uiFeeReceiver
                );

            result.estimatedOutputUsd =
                expectedSwapOutput *
                values.shortTokenPrice;
        }

        if (breakdown.positionInfo.pnlAfterPriceImpactUsd > 0) {
            result.estimatedOutputUsd += SignedMath.abs(
                breakdown.positionInfo.pnlAfterPriceImpactUsd
            );
        }

        result.executionPrice = breakdown
            .positionInfo
            .executionPriceResult
            .executionPrice;
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

    function _getPositionInfo(
        IGmxFrfStrategyManager manager,
        address account,
        address market,
        uint256 sizeDeltaUsd,
        bool useMaxSizeDelta
    ) private view returns (IGmxV2PositionTypes.PositionInfo memory position) {
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
}

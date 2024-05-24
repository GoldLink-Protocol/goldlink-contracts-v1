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
import { IStrategyBank } from "../../../interfaces/IStrategyBank.sol";
import { DeltaConvergenceMath } from "./DeltaConvergenceMath.sol";
import { AccountGetters } from "./AccountGetters.sol";
import { Pricing } from "./Pricing.sol";
import {
    StrategyBankHelpers
} from "../../../libraries/StrategyBankHelpers.sol";
import { PercentMath } from "../../../libraries/PercentMath.sol";
import { GmxFrfStrategyErrors } from "../GmxFrfStrategyErrors.sol";
import { SwapCallbackLogic } from "./SwapCallbackLogic.sol";

/**
 * @title WithdrawalLogic
 * @author GoldLink
 *
 * @dev Logic for managing profit withdrawals.
 */
library WithdrawalLogic {
    using PercentMath for uint256;
    using SafeERC20 for IERC20;

    // ============ Structs ============

    struct WithdrawProfitParams {
        address market;
        uint256 amount;
        address recipient;
    }

    // ============ External Functions ============

    /**
     * @notice Withdraw profit from the account up to the configured profit margin. When withdrawing profit,
     * the value of the account should never go below the value of the account's `loan` + `minWithdrawalBufferPercent`.
     * @param manager   The configuration manager for the strategy.
     * @param account   The account that is attempting to withdraw profit.
     * @param params    Withdrawal related parameters.
     */
    function withdrawProfit(
        IGmxFrfStrategyManager manager,
        IStrategyBank bank,
        address account,
        WithdrawProfitParams memory params
    ) external {
        // Return early if amount is 0.
        if (params.amount == 0) {
            return;
        }

        // Make sure that the delta of the position is respected when removing assets from the account.
        verifyMarketAssetRemoval(
            manager,
            params.market,
            account,
            params.amount
        );

        address asset = GmxMarketGetters.getLongToken(
            manager.gmxV2DataStore(),
            params.market
        );

        // At this point, it is known that the withdrawal respects the delta of the position. However,
        // the account's value must be checked against its loan and remaining collateral to ensure that the withdrawn funds do not
        // result in a value that is less than the account's loan times the configured `withdrawalBufferPercent`.

        {
            // The first step to verify the account's solvency for a withdrawal is to compute the current value of the account in terms of USDC.
            uint256 accountValueUSDC = AccountGetters.getAccountValueUsdc(
                manager,
                account
            );

            // In order to withdraw profits, the account's value after the withdrawal must be above the minimum open health score.
            uint256 withdrawalValueUSD = Pricing.getTokenValueUSD(
                manager,
                asset,
                params.amount
            );

            uint256 withdrawalValueUSDC = Pricing.getTokenAmountForUSD(
                manager,
                address(manager.USDC()),
                withdrawalValueUSD
            );

            // To make sure that the value of the withdrawal does not exceed the account value. This also prevents underflow causing a revert without
            // proper cause in the subtraction below.
            require(
                withdrawalValueUSDC < accountValueUSDC,
                GmxFrfStrategyErrors
                    .WITHDRAWAL_VALUE_CANNOT_BE_GTE_ACCOUNT_VALUE
            );

            // Make sure to get the holdings after paying interest. Interest accrued must be considered when checking the health score.
            IStrategyBank.StrategyAccountHoldings memory holdings = bank
                .getStrategyAccountHoldingsAfterPayingInterest(account);

            uint256 withdrawalBuffer = manager
                .getProfitWithdrawalBufferPercent();

            // The value of the account less the withdrawn value must be greater than the account's loan. If this were not the case,
            // you could open a loan above the minimum open health score and withdraw assets.
            // Note: The manager prevents the `withdrawalBuffer` from being less than 100%, so its impossible to divide by zero here.
            require(
                accountValueUSDC - withdrawalValueUSDC >
                    holdings.loan.percentToFraction(withdrawalBuffer),
                GmxFrfStrategyErrors
                    .CANNOT_WITHDRAW_BELOW_THE_ACCOUNTS_LOAN_VALUE_WITH_BUFFER_APPLIED
            );

            // Get the health score of the account after the withdrawal has been accounted for to ensure it abides by the strategy's minimum open health
            // score requirements.
            uint256 healthScore = StrategyBankHelpers.getHealthScore(
                holdings,
                accountValueUSDC - withdrawalValueUSDC
            );

            require(
                healthScore >= bank.minimumOpenHealthScore_(),
                GmxFrfStrategyErrors
                    .WITHDRAWAL_BRINGS_ACCOUNT_BELOW_MINIMUM_OPEN_HEALTH_SCORE
            );
        }

        // Since all checks pass, withdraw the funds.
        IERC20(asset).safeTransfer(params.recipient, params.amount);
    }

    /**
     * @notice Swap tokens for USDC, allowing an account to use funding fees paid in longTokens
     * to repay their loan.
     * @param manager            The configuration manager for the strategy.
     * @param market             The market to swap the `longToken` of for USDC.
     * @param account            The strategy account address that is swapping tokens.
     * @param longTokenAmountOut The amount of the `market.longToken` to sell for USDC.
     * @param callback           The address of the callback handler. This address must be a smart contract that implements the
     * `ISwapCallbackHandler` interface.
     * @param receiver           The address that the `longToken` should be sent to.
     * @param data               Data passed through to the callback contract.
     */
    function swapTokensForUSDC(
        IGmxFrfStrategyManager manager,
        address market,
        address account,
        uint256 longTokenAmountOut,
        address callback,
        address receiver,
        bytes memory data
    ) external returns (uint256 amountReceived) {
        // Return early if amount is zero.
        if (longTokenAmountOut == 0) {
            return 0;
        }

        // Make sure that the delta of the account's positions is respected.
        verifyMarketAssetRemoval(manager, market, account, longTokenAmountOut);

        address longToken = GmxMarketGetters.getLongToken(
            manager.gmxV2DataStore(),
            market
        );

        // Need to get the market configuration in order to pass in the proper `maxSlippageAmount` to the swap callback handler.
        IGmxFrfStrategyManager.MarketConfiguration memory marketConfig = manager
            .getMarketConfiguration(market);

        // Execute the callback, returning the amount of USDC that was received by the contract.
        return
            SwapCallbackLogic.handleSwapCallback(
                manager,
                longToken,
                longTokenAmountOut,
                marketConfig.orderPricingParameters.maxSwapSlippagePercent,
                callback,
                receiver,
                data
            );
    }

    // ============ Public Functions ============

    /**
     * @notice Verify that reducing the amount of `market.longToken` from the account's holdings
     * will not increase the directional risk of a strategy account.
     * @param manager             The configuration manager for the strategy.
     * @param market              The market to swap the `longToken` of for USDC.
     * @param account             The strategy account address that `longTokens` are being removed from.
     * @param tokenAmountRemoving The amount of the `market.longToken` that is being removed from the account.
     */
    function verifyMarketAssetRemoval(
        IGmxFrfStrategyManager manager,
        address market,
        address account,
        uint256 tokenAmountRemoving
    ) public view {
        // Return early if amount is 0.
        if (tokenAmountRemoving == 0) {
            return;
        }

        // First, we get the position information (if it exists). We do this because we need to make sure that the delta of the position is respected when withdrawing profit.
        DeltaConvergenceMath.PositionTokenBreakdown
            memory breakdown = DeltaConvergenceMath.getAccountMarketDelta(
                manager,
                account,
                market,
                0,
                true
            );

        // Make sure the requested withdrawal amount does not exceed the current long token balance of the account.
        require(
            breakdown.accountBalanceLongTokens >= tokenAmountRemoving,
            GmxFrfStrategyErrors
                .CANNOT_WITHDRAW_MORE_TOKENS_THAN_ACCOUNT_BALANCE
        );

        {
            // Check to make sure the position's delta is long (more long tokens then short). This prevents the below subtraction from reverting due to underflow.
            require(
                breakdown.tokensShort < breakdown.tokensLong,
                GmxFrfStrategyErrors
                    .CANNOT_WITHDRAW_FROM_MARKET_IF_ACCOUNT_MARKET_DELTA_IS_SHORT
            );

            // The maximum amount that can be withdrawn is the amount that perfectly aligns the position's delta.
            uint256 difference = breakdown.tokensLong - breakdown.tokensShort;

            // Check to make sure that the amount of tokens being removed is less than the difference in the
            // sizeInTokens of the account's long position - short position.
            require(
                tokenAmountRemoving <= difference,
                GmxFrfStrategyErrors
                    .REQUESTED_WITHDRAWAL_AMOUNT_EXCEEDS_CURRENT_DELTA_DIFFERENCE
            );
        }
    }
}

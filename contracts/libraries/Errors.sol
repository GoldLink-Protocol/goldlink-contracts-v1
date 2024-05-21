// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

/**
 * @title Errors
 * @author GoldLink
 *
 * @dev The core GoldLink Protocol errors library.
 */
library Errors {
    //
    // COMMON
    //
    string internal constant ADDRESS_CANNOT_BE_RESET =
        "Address cannot be reset.";
    string internal constant CALLER_MUST_BE_VALID_STRATEGY_BANK =
        "Caller must be valid strategy bank.";
    string internal constant CANNOT_CALL_FUNCTION_WHEN_PAUSED =
        "Cannot call function when paused.";
    string internal constant ZERO_ADDRESS_IS_NOT_ALLOWED =
        "Zero address is not allowed.";
    string internal constant ZERO_AMOUNT_IS_NOT_VALID =
        "Zero amount is not valid.";

    //
    // UTILS
    //
    string internal constant CANNOT_RENOUNCE_OWNERSHIP =
        "GoldLinkOwnable: Cannot renounce ownership";

    //
    // STRATEGY ACCOUNT
    //
    string internal constant STRATEGY_ACCOUNT_ACCOUNT_IS_NOT_LIQUIDATABLE =
        "StrategyAccount: Account is not liquidatable.";
    string internal constant STRATEGY_ACCOUNT_ACCOUNT_HAS_AN_ACTIVE_LOAN =
        "StrategyAccount: Account has an active loan.";
    string internal constant STRATEGY_ACCOUNT_ACCOUNT_HAS_NO_LOAN =
        "StrategyAccount: Account has no loan.";
    string
        internal constant STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_ACTIVE =
        "StrategyAccount: Cannot call while liquidation active.";
    string
        internal constant STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_INACTIVE =
        "StrategyAccount: Cannot call while liquidation inactive.";
    string
        internal constant STRATEGY_ACCOUNT_CANNOT_PROCESS_LIQUIDATION_WHEN_NOT_COMPLETE =
        "StrategyAccount: Cannot process liquidation when not complete.";
    string internal constant STRATEGY_ACCOUNT_PARAMETERS_LENGTH_MISMATCH =
        "StrategyAccount: Parameters length mismatch.";
    string internal constant STRATEGY_ACCOUNT_SENDER_IS_NOT_OWNER =
        "StrategyAccount: Sender is not owner.";

    //
    // STRATEGY BANK
    //
    string
        internal constant STRATEGY_BANK_CALLER_IS_NOT_VALID_STRATEGY_ACCOUNT =
        "StrategyBank: Caller is not valid strategy account.";
    string internal constant STRATEGY_BANK_CALLER_MUST_BE_STRATEGY_RESERVE =
        "StrategyBank: Caller must be strategy reserve.";
    string
        internal constant STRATEGY_BANK_CANNOT_DECREASE_COLLATERAL_BELOW_ZERO =
        "StrategyBank: Cannot decrease collateral below zero.";
    string internal constant STRATEGY_BANK_CANNOT_REPAY_LOAN_WHEN_LIQUIDATABLE =
        "StrategyBank: Cannot repay loan when liquidatable.";
    string
        internal constant STRATEGY_BANK_CANNOT_REPAY_MORE_THAN_IS_IN_STRATEGY_ACCOUNT =
        "StrategyBank: Cannot repay more than is in strategy account.";
    string internal constant STRATEGY_BANK_CANNOT_REPAY_MORE_THAN_TOTAL_LOAN =
        "StrategyBank: Cannot repay more than total loan.";
    string
        internal constant STRATEGY_BANK_COLLATERAL_WOULD_BE_LESS_THAN_MINIMUM =
        "StrategyBank: Collateral would be less than minimum.";
    string
        internal constant STRATEGY_BANK_EXECUTOR_PREMIUM_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT =
        "StrategyBank: Executor premium must be less than one hundred percent.";
    string
        internal constant STRATEGY_BANK_HEALTH_SCORE_WOULD_FALL_BELOW_MINIMUM_OPEN_HEALTH_SCORE =
        "StrategyBank: Health score would fall below minimum open health score.";
    string
        internal constant STRATEGY_BANK_INSURANCE_PREMIUM_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT =
        "StrategyBank: Insurance premium must be less than one hundred percent.";
    string
        internal constant STRATEGY_BANK_LIQUIDATABLE_HEALTH_SCORE_MUST_BE_GREATER_THAN_ZERO =
        "StrategyBank: Liquidatable health score must be greater than zero.";
    string
        internal constant STRATEGY_BANK_LIQUIDATABLE_HEALTH_SCORE_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT =
        "StrategyBank: Liquidatable health score must be less than one hundred percent.";
    string
        internal constant STRATEGY_BANK_LIQUIDATION_INSURANCE_PREMIUM_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT =
        "StrategyBank: Liquidation insurance premium must be less than one hundred percent.";
    string
        internal constant STRATEGY_BANK_MINIMUM_OPEN_HEALTH_SCORE_CANNOT_BE_AT_OR_BELOW_LIQUIDATABLE_HEALTH_SCORE =
        "StrategyBank: Minimum open health score cannot be at or below liquidatable health score.";
    string
        internal constant STRATEGY_BANK_REQUESTED_WITHDRAWAL_AMOUNT_EXCEEDS_AVAILABLE_COLLATERAL =
        "StrategyBank: Requested withdrawal amount exceeds available collateral.";

    //
    // STRATEGY RESERVE
    //
    string internal constant STRATEGY_RESERVE_CALLER_MUST_BE_THE_STRATEGY_BANK =
        "StrategyReserve: Caller must be the strategy bank.";
    string internal constant STRATEGY_RESERVE_INSUFFICIENT_AVAILABLE_TO_BORROW =
        "StrategyReserve: Insufficient available to borrow.";
    string
        internal constant STRATEGY_RESERVE_OPTIMAL_UTILIZATION_MUST_BE_LESS_THAN_OR_EQUAL_TO_ONE_HUNDRED_PERCENT =
        "StrategyReserve: Optimal utilization must be less than or equal to one hundred percent.";
    string
        internal constant STRATEGY_RESERVE_STRATEGY_ASSET_DOES_NOT_HAVE_ASSET_DECIMALS_SET =
        "StrategyReserve: Strategy asset does not have asset decimals set.";

    //
    // STRATEGY CONTROLLER
    //
    string internal constant STRATEGY_CONTROLLER_CALLER_IS_NOT_STRATEGY_CORE =
        "StrategyController: Caller is not strategy core.";
    string internal constant STRATEGY_CONTROLLER_LOCK_ALREADY_ACQUIRED =
        "StrategyController: Lock already acquired.";
    string internal constant STRATEGY_CONTROLLER_LOCK_NOT_ACQUIRED =
        "StrategyController: Lock not acquired.";
}

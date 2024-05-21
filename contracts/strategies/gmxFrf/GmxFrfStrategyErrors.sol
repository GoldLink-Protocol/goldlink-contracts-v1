// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

/**
 * @title GmxFrfStrategyErrors
 * @author GoldLink
 *
 * @dev Gmx Delta Neutral Errors library for GMX related interactions.
 */
library GmxFrfStrategyErrors {
    //
    // COMMON
    //
    string internal constant ZERO_ADDRESS_IS_NOT_ALLOWED =
        "Zero address is not allowed.";
    string
        internal constant TOO_MUCH_NATIVE_TOKEN_SPENT_IN_MULTICALL_EXECUTION =
        "Too much native token spent in multicall transaction.";
    string internal constant MSG_VALUE_LESS_THAN_PROVIDED_EXECUTION_FEE =
        "Msg value less than provided execution fee.";
    string internal constant NESTED_MULTICALLS_ARE_NOT_ALLOWED =
        "Nested multicalls are not allowed.";

    //
    // Deployment Configuration Manager
    //
    string
        internal constant DEPLOYMENT_CONFIGURATION_MANAGER_INVALID_DEPLOYMENT_ADDRESS =
        "DeploymentConfigurationManager: Invalid deployment address.";

    //
    // GMX Delta Neutral Funding Rate Farming Manager
    //
    string internal constant CANNOT_ADD_SEPERATE_MARKET_WITH_SAME_LONG_TOKEN =
        "GmxFrfStrategyManager: Cannot add seperate market with same long token.";
    string
        internal constant GMX_FRF_STRATEGY_MANAGER_LONG_TOKEN_DOES_NOT_HAVE_AN_ORACLE =
        "GmxFrfStrategyManager: Long token does not have an oracle.";
    string internal constant GMX_FRF_STRATEGY_MANAGER_MARKET_DOES_NOT_EXIST =
        "GmxFrfStrategyManager: Market does not exist.";
    string
        internal constant GMX_FRF_STRATEGY_MANAGER_SHORT_TOKEN_DOES_NOT_HAVE_AN_ORACLE =
        "GmxFrfStrategyManager: Short token does not have an oracle.";
    string internal constant GMX_FRF_STRATEGY_MANAGER_SHORT_TOKEN_MUST_BE_USDC =
        "GmxFrfStrategyManager: Short token for market must be usdc.";
    string internal constant LONG_TOKEN_CANT_BE_USDC =
        "GmxFrfStrategyManager: Long token can't be usdc.";
    string internal constant MARKET_CAN_ONLY_BE_DISABLED_IN_DECREASE_ONLY_MODE =
        "GmxFrfStrategyManager: Market can only be disabled in decrease only mode.";
    string internal constant MARKETS_COUNT_CANNOT_EXCEED_MAXIMUM =
        "GmxFrfStrategyManager: Market count cannot exceed maximum.";
    string internal constant MARKET_INCREASES_ARE_ALREADY_DISABLED =
        "GmxFrfStrategyManager: Market increases are already disabled.";
    string internal constant MARKET_IS_NOT_ENABLED =
        "GmxFrfStrategyManager: Market is not enabled.";

    //
    // GMX V2 Adapter
    //
    string
        internal constant GMX_V2_ADAPTER_MAX_SLIPPAGE_MUST_BE_LT_100_PERCENT =
        "GmxV2Adapter: Maximum slippage must be less than 100%.";
    string internal constant GMX_V2_ADAPTER_MINIMUM_SLIPPAGE_MUST_BE_LT_MAX =
        "GmxV2Adapter: Minimum slippage must be less than maximum slippage.";

    //
    // Liquidation Management
    //
    string
        internal constant LIQUIDATION_MANAGEMENT_AVAILABLE_TOKEN_BALANCE_MUST_BE_CLEARED_BEFORE_REBALANCING =
        "LiquidationManagement: Available token balance must be cleared before rebalancing.";
    string
        internal constant LIQUIDATION_MANAGEMENT_NO_ASSETS_EXIST_IN_THIS_MARKET_TO_REBALANCE =
        "LiquidationManagement: No assets exist in this market to rebalance.";
    string
        internal constant LIQUIDATION_MANAGEMENT_POSITION_DELTA_IS_NOT_SUFFICIENT_FOR_SWAP_REBALANCE =
        "LiquidationManagement: Position delta is not sufficient for swap rebalance.";
    string
        internal constant LIQUIDATION_MANAGEMENT_POSITION_IS_WITHIN_MAX_DEVIATION =
        "LiquidationManagement: Position is within max deviation.";
    string
        internal constant LIQUIDATION_MANAGEMENT_POSITION_IS_WITHIN_MAX_LEVERAGE =
        "LiquidationManagement: Position is within max leverage.";
    string
        internal constant LIQUIDATION_MANAGEMENT_REBALANCE_AMOUNT_LEAVE_TOO_LITTLE_REMAINING_ASSETS =
        "LiquidationManagement: Rebalance amount leaves too little remaining assets.";

    //
    // Swap Callback Logic
    //
    string
        internal constant SWAP_CALLBACK_LOGIC_CALLBACK_ADDRESS_MUST_NOT_HAVE_GMX_CONTROLLER_ROLE =
        "SwapCallbackLogic: Callback address must not have GMX controller role.";
    string internal constant SWAP_CALLBACK_LOGIC_CANNOT_SWAP_USDC =
        "SwapCallbackLogic: Cannot swap USDC.";
    string internal constant SWAP_CALLBACK_LOGIC_INSUFFICIENT_USDC_RETURNED =
        "SwapCallbackLogic: Insufficient USDC returned.";
    string
        internal constant SWAP_CALLBACK_LOGIC_NO_BALANCE_AFTER_SLIPPAGE_APPLIED =
        "SwapCallbackLogic: No balance after slippage applied.";

    //
    // Order Management
    //
    string internal constant ORDER_MANAGEMENT_INVALID_FEE_REFUND_RECIPIENT =
        "OrderManagement: Invalid fee refund recipient.";
    string
        internal constant ORDER_MANAGEMENT_LIQUIDATION_ORDER_CANNOT_BE_CANCELLED_YET =
        "OrderManagement: Liquidation order cannot be cancelled yet.";
    string internal constant ORDER_MANAGEMENT_ORDER_MUST_BE_FOR_THIS_ACCOUNT =
        "OrderManagement: Order must be for this account.";

    //
    // Order Validation
    //
    string
        internal constant ORDER_VALIDATION_ACCEPTABLE_PRICE_IS_NOT_WITHIN_SLIPPAGE_BOUNDS =
        "OrderValidation: Acceptable price is not within slippage bounds.";
    string internal constant ORDER_VALIDATION_DECREASE_AMOUNT_CANNOT_BE_ZERO =
        "OrderValidation: Decrease amount cannot be zero.";
    string internal constant ORDER_VALIDATION_DECREASE_AMOUNT_IS_TOO_LARGE =
        "OrderValidation: Decrease amount is too large.";
    string
        internal constant ORDER_VALIDATION_EXECUTION_PRICE_NOT_WITHIN_SLIPPAGE_RANGE =
        "OrderValidation: Execution price not within slippage range.";
    string
        internal constant ORDER_VALIDATION_INITIAL_COLLATERAL_BALANCE_IS_TOO_LOW =
        "OrderValidation: Initial collateral balance is too low.";
    string internal constant ORDER_VALIDATION_MARKET_HAS_PENDING_ORDERS =
        "OrderValidation: Market has pending orders.";
    string internal constant ORDER_VALIDATION_ORDER_TYPE_IS_DISABLED =
        "OrderValidation: Order type is disabled.";
    string internal constant ORDER_VALIDATION_ORDER_SIZE_IS_TOO_LARGE =
        "OrderValidation: Order size is too large.";
    string internal constant ORDER_VALIDATION_ORDER_SIZE_IS_TOO_SMALL =
        "OrderValidation: Order size is too small.";
    string internal constant ORDER_VALIDATION_POSITION_DOES_NOT_EXIST =
        "OrderValidation: Position does not exist.";
    string
        internal constant ORDER_VALIDATION_POSITION_NOT_OWNED_BY_THIS_ACCOUNT =
        "OrderValidation: Position not owned by this account.";
    string internal constant ORDER_VALIDATION_POSITION_SIZE_IS_TOO_LARGE =
        "OrderValidation: Position size is too large.";
    string internal constant ORDER_VALIDATION_POSITION_SIZE_IS_TOO_SMALL =
        "OrderValidation: Position size is too small.";
    string
        internal constant ORDER_VALIDATION_PROVIDED_EXECUTION_FEE_IS_TOO_LOW =
        "OrderValidation: Provided execution fee is too low.";
    string internal constant ORDER_VALIDATION_SWAP_SLIPPAGE_IS_TOO_HGIH =
        "OrderValidation: Swap slippage is too high.";

    //
    // Gmx Funding Rate Farming
    //
    string internal constant GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST =
        "GmxFrfStrategyAccount: Market does not exist.";
    string
        internal constant GMX_FRF_STRATEGY_ORDER_CALLBACK_RECEIVER_CALLER_MUST_HAVE_CONTROLLER_ROLE =
        "GmxFrfStrategyAccount: Caller must have controller role.";

    //
    // Gmx V2 Order Callback Receiver
    //
    string
        internal constant GMX_V2_ORDER_CALLBACK_RECEIVER_CALLER_MUST_HAVE_CONTROLLER_ROLE =
        "GmxV2OrderCallbackReceiver: Caller must have controller role.";

    //
    // Market Configuration Manager
    //
    string
        internal constant ASSET_LIQUIDATION_FEE_CANNOT_BE_GREATER_THAN_MAXIMUM =
        "MarketConfigurationManager: Asset liquidation fee cannot be greater than maximum.";
    string internal constant ASSET_ORACLE_COUNT_CANNOT_EXCEED_MAXIMUM =
        "MarketConfigurationManager: Asset oracle count cannot exceed maximum.";
    string
        internal constant CANNOT_SET_MAX_POSITION_SLIPPAGE_BELOW_MINIMUM_VALUE =
        "MarketConfigurationManager: Cannot set maxPositionSlippagePercent below the minimum value.";
    string
        internal constant CANNOT_SET_THE_CALLBACK_GAS_LIMIT_ABOVE_THE_MAXIMUM =
        "MarketConfigurationManager: Cannot set the callback gas limit above the maximum.";
    string internal constant CANNOT_SET_MAX_SWAP_SLIPPAGE_BELOW_MINIMUM_VALUE =
        "MarketConfigurationManager: Cannot set maxSwapSlippagePercent below minimum value.";
    string
        internal constant CANNOT_SET_THE_EXECUTION_FEE_BUFFER_ABOVE_THE_MAXIMUM =
        "MarketConfigurationManager: Cannot set the execution fee buffer above the maximum.";
    string
        internal constant MARKET_CONFIGURATION_MANAGER_MIN_ORDER_SIZE_MUST_BE_LESS_THAN_OR_EQUAL_TO_MAX_ORDER_SIZE =
        "MarketConfigurationManager: Min order size must be less than or equal to max order size.";
    string
        internal constant MARKET_CONFIGURATION_MANAGER_MIN_POSITION_SIZE_MUST_BE_LESS_THAN_OR_EQUAL_TO_MAX_POSITION_SIZE =
        "MarketConfigurationManager: Min position size must be less than or equal to max position size.";
    string
        internal constant MAX_DELTA_PROPORTION_IS_BELOW_THE_MINIMUM_REQUIRED_VALUE =
        "MarketConfigurationManager: MaxDeltaProportion is below the minimum required value.";
    string
        internal constant MAX_POSITION_LEVERAGE_IS_BELOW_THE_MINIMUM_REQUIRED_VALUE =
        "MarketConfigurationManager: MaxPositionLeverage is below the minimum required value.";
    string internal constant UNWIND_FEE_IS_ABOVE_THE_MAXIMUM_ALLOWED_VALUE =
        "MarketConfigurationManager: UnwindFee is above the maximum allowed value.";
    string
        internal constant WITHDRAWAL_BUFFER_PERCENTAGE_MUST_BE_GREATER_THAN_THE_MINIMUM =
        "MarketConfigurationManager: WithdrawalBufferPercentage must be greater than the minimum.";
    //
    // Withdrawal Logic Errors
    //
    string
        internal constant CANNOT_WITHDRAW_BELOW_THE_ACCOUNTS_LOAN_VALUE_WITH_BUFFER_APPLIED =
        "WithdrawalLogic: Cannot withdraw to below the account's loan value with buffer applied.";
    string
        internal constant CANNOT_WITHDRAW_FROM_MARKET_IF_ACCOUNT_MARKET_DELTA_IS_SHORT =
        "WithdrawalLogic: Cannot withdraw from market if account's market delta is short.";
    string internal constant CANNOT_WITHDRAW_MORE_TOKENS_THAN_ACCOUNT_BALANCE =
        "WithdrawalLogic: Cannot withdraw more tokens than account balance.";
    string
        internal constant REQUESTED_WITHDRAWAL_AMOUNT_EXCEEDS_CURRENT_DELTA_DIFFERENCE =
        "WithdrawalLogic: Requested amount exceeds current delta difference.";
    string
        internal constant WITHDRAWAL_BRINGS_ACCOUNT_BELOW_MINIMUM_OPEN_HEALTH_SCORE =
        "WithdrawalLogic: Withdrawal brings account below minimum open health score.";
    string internal constant WITHDRAWAL_VALUE_CANNOT_BE_GTE_ACCOUNT_VALUE =
        "WithdrawalLogic: Withdrawal value cannot be gte to account value.";
}

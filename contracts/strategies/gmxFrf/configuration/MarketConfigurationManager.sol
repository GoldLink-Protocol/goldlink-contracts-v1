// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IMarketConfiguration } from "../interfaces/IMarketConfiguration.sol";
import { GmxFrfStrategyErrors } from "../GmxFrfStrategyErrors.sol";
import { Limits } from "../libraries/Limits.sol";

/**
 * @title GmxV2Configuration
 * @author GoldLink
 *
 * @dev Storage related to GMX market configurations.
 */
abstract contract MarketConfigurationManager is
    IMarketConfiguration,
    Initializable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Storage Variables ============

    /// @dev Set of available markets.
    EnumerableSet.AddressSet private markets_;

    /// @dev Mapping of markets to their Pricing Parameters
    mapping(address => OrderPricingParameters) private marketPricingParameters_;

    /// @dev Mapping of markets to their Position Parameters
    mapping(address => PositionParameters) private marketPositionParameters_;

    /// @dev Mapping of markets to their Unwind Parameters
    mapping(address => UnwindParameters) private marketUnwindParameters_;

    /// @dev Mapping of assets to their liquidation fee percent. Percents are denoted with 1e18 is 100%.
    mapping(address => uint256) private assetLiquidationFeePercent_;

    /// @dev Liquidation order timeout deadline.
    uint256 private liquidationOrderTimeoutDeadline_;

    /// @dev The minimum callback gas limit passed in. This prevents users from forcing the callback to run out of gas
    // and disrupting the contract's state, as it relies on the callback being executed.
    uint256 private callbackGasLimit_;

    /// @dev The minimum execution fee buffer percentage required to be provided by the user. This is the percentage of the initially calculated execution fee
    // that needs to be provided additionally to prevent orders from failing execution.
    uint256 private executionFeeBufferPercent_;

    /// @dev Gmx V2 referral address to use for orders.
    bytes32 private referralCode_;

    /// @dev UI fee receiver address.
    address private uiFeeReceiver_;

    /// @dev The minimum percentage above an account's loan that the value must be above when withdrawing.
    /// To disable withdrawls while a loan is active (funds can always be withdrawn when a loan is inactive),
    /// set to max uint256.
    uint256 private withdrawalBufferPercentage_;

    /**
     * @dev This is empty reserved space intended to allow future versions of this upgradeable
     *  contract to define new variables without shifting down storage in the inheritance chain.
     *  See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[39] private __gap;

    // ============ Initializer ============

    function __MarketConfigurationManager_init(
        SharedOrderParameters calldata sharedOrderParameters,
        uint256 liquidationOrderTimeDeadline
    ) internal onlyInitializing {
        __MarketConfigurationManager_init_unchained(
            sharedOrderParameters,
            liquidationOrderTimeDeadline
        );
    }

    function __MarketConfigurationManager_init_unchained(
        SharedOrderParameters calldata sharedOrderParameters,
        uint256 liquidationOrderTimeDeadline
    ) internal onlyInitializing {
        _setCallbackGasLimit(sharedOrderParameters.callbackGasLimit);
        _setExecutionFeeBufferPercent(
            sharedOrderParameters.executionFeeBufferPercent
        );
        _setReferralCode(sharedOrderParameters.referralCode);
        _setUiFeeReceiver(sharedOrderParameters.uiFeeReceiver);
        _setLiquidationOrderTimeoutDeadline(liquidationOrderTimeDeadline);
        _setWithdrawalBufferPercentage(
            sharedOrderParameters.withdrawalBufferPercentage
        );
    }

    // ============ External Functions ============

    /**
     * @notice Get the unwind configuration for a specific market.
     * @param market                  The market to get the unwind configuration for.
     * @return marketUnwindParameters The market specific parameters for unwinding a position.
     */
    function getMarketUnwindConfiguration(
        address market
    ) external view returns (UnwindParameters memory marketUnwindParameters) {
        return marketUnwindParameters_[market];
    }

    /**
     * @notice Get the asset liquidation fee percent for the specified asset. Percents are denoted with 1e18 is 100%.
     * @param asset                  The asset to get the liquidation fee percent for.
     * @return liquidationFeePercent The liquidation fee percent for a specific asset.
     */
    function getAssetLiquidationFeePercent(
        address asset
    ) external view returns (uint256 liquidationFeePercent) {
        return assetLiquidationFeePercent_[asset];
    }

    /**
     * @notice Get the configured liquidation order timeout deadline.
     * @return liquidationOrderTimeoutDeadline The time after which a liquidation order can be canceled.
     */
    function getLiquidationOrderTimeoutDeadline()
        external
        view
        returns (uint256 liquidationOrderTimeoutDeadline)
    {
        return liquidationOrderTimeoutDeadline_;
    }

    /**
     * @notice Get the configured callback gas limit.
     * @return callbackGasLimit The gas limit on a callback, how much gas a callback can cost.
     */
    function getCallbackGasLimit()
        external
        view
        returns (uint256 callbackGasLimit)
    {
        return callbackGasLimit_;
    }

    /**
     * @notice Get the configured execution fee buffer percentage.
     * @return executionFeeBufferPercent The percentage of the initially calculated execution fee that needs to be provided additionally
     * to prevent orders from failing execution.
     */
    function getExecutionFeeBufferPercent()
        external
        view
        returns (uint256 executionFeeBufferPercent)
    {
        return executionFeeBufferPercent_;
    }

    /**
     * @notice Get the configured referral code.
     * @return referralCode The code applied to all orders for the strategy, tying orders back to
     * this protocol.
     */
    function getReferralCode() external view returns (bytes32 referralCode) {
        return referralCode_;
    }

    /**
     * @notice Get the configured UI fee receiver.
     * @return uiFeeReceiver The fee paid to the UI, this protocol for placing orders.
     */
    function getUiFeeReceiver() external view returns (address uiFeeReceiver) {
        return uiFeeReceiver_;
    }

    /**
     * @notice Get the configured minimumWithdrawalBufferPercentage.
     * @return percentage The current withdrawalBufferPercentage.
     */
    function getProfitWithdrawalBufferPercent()
        external
        view
        returns (uint256 percentage)
    {
        return withdrawalBufferPercentage_;
    }

    // ============ Public Functions ============

    /**
     * @notice Get the configuration information for a specific market.
     * @param market               The market to get the configuration for.
     * @return marketConfiguration The configuration for a specific market.
     */
    function getMarketConfiguration(
        address market
    )
        public
        view
        override
        returns (MarketConfiguration memory marketConfiguration)
    {
        return
            MarketConfiguration({
                orderPricingParameters: marketPricingParameters_[market],
                sharedOrderParameters: SharedOrderParameters({
                    callbackGasLimit: callbackGasLimit_,
                    executionFeeBufferPercent: executionFeeBufferPercent_,
                    referralCode: referralCode_,
                    uiFeeReceiver: uiFeeReceiver_,
                    withdrawalBufferPercentage: withdrawalBufferPercentage_
                }),
                positionParameters: marketPositionParameters_[market],
                unwindParameters: marketUnwindParameters_[market]
            });
    }

    /**
     * @notice Check whether or not a market address is approved for the strategy.
     * @param market      The market to recieve the approval status for.
     * @return isApproved If the market is approved for the strategy.
     */
    function isApprovedMarket(
        address market
    ) public view returns (bool isApproved) {
        return markets_.contains(market);
    }

    /**
     * @notice Get all available markets for the strategy.
     * @return markets The markets supported for this strategy. All markets that delta-neutral positions
     * can be placed on for this strategy.
     */
    function getAvailableMarkets()
        public
        view
        override
        returns (address[] memory markets)
    {
        return markets_.values();
    }

    // ============ Internal Functions ============

    /**
     * @notice Set the configuration for a specific market.
     * @dev Emits the `MarketConfigurationSet()` event.
     * @param orderPricingParams The parameters dictating pricing for the market.
     * @param positionParams     The parameters dictating establishing/maintaining a position for
     * the market.
     * @param unwindParameters   The parameters dictating when a position can be unwound for the market.
     */
    function _setMarketConfiguration(
        address market,
        OrderPricingParameters memory orderPricingParams,
        PositionParameters memory positionParams,
        UnwindParameters memory unwindParameters
    ) internal {
        // Make sure we are not exceeding maximum market count.
        require(
            markets_.contains(market) ||
                markets_.length() < Limits.MAX_MARKET_COUNT,
            GmxFrfStrategyErrors.MARKETS_COUNT_CANNOT_EXCEED_MAXIMUM
        );

        // Validate order and position parameters.
        _validateOrderPricingParameters(orderPricingParams);
        _validatePositionParameters(positionParams);
        _validateUnwindParameters(unwindParameters);

        // Add market to registered markets.
        markets_.add(market);

        // Set all new market parameters.
        marketPricingParameters_[market] = orderPricingParams;
        marketPositionParameters_[market] = positionParams;
        marketUnwindParameters_[market] = unwindParameters;

        emit MarketConfigurationSet(
            market,
            orderPricingParams,
            positionParams,
            unwindParameters
        );
    }

    /**
     * @notice Set the asset liquidation fee percent for a specific asset. There is a maximum fee
     * of 10% (1e17) to prevent a bad owner from stealing all assets in an account.
     * @dev Emits the `AssetLiquidationFeeSet()` event.
     * @param asset                    The asset to set the liquidation fee for.
     * @param newLiquidationFeePercent The fee percentage that is paid to liquidators when selling this asset.
     */
    function _setAssetLiquidationFeePercent(
        address asset,
        uint256 newLiquidationFeePercent
    ) internal {
        require(
            newLiquidationFeePercent <=
                Limits.MAXIMUM_ASSET_LIQUIDATION_FEE_PERCENT,
            GmxFrfStrategyErrors
                .ASSET_LIQUIDATION_FEE_CANNOT_BE_GREATER_THAN_MAXIMUM
        );
        assetLiquidationFeePercent_[asset] = newLiquidationFeePercent;
        emit AssetLiquidationFeeSet(asset, newLiquidationFeePercent);
    }

    /**
     * @notice Set the liquidation order timeout deadline, which is the amount of time that must pass before
     * a liquidation order can be cancelled.
     * @dev Emits the `LiquidationOrderTimeoutDeadlineSet()` event.
     * @param newLiquidationOrderTimeoutDeadline The new liquidation order timeout to use for all liquidation orders.
     */
    function _setLiquidationOrderTimeoutDeadline(
        uint256 newLiquidationOrderTimeoutDeadline
    ) internal {
        liquidationOrderTimeoutDeadline_ = newLiquidationOrderTimeoutDeadline;
        emit LiquidationOrderTimeoutDeadlineSet(
            newLiquidationOrderTimeoutDeadline
        );
    }

    /**
     * @notice Set the callback gas limit for the strategy. Setting this value too low results in callback
     * execution failures which must be avoided. Setting this value too high
     * requires the user to provide a higher execution fee, which will ultimately be rebated if not used.
     * A configured limit prevents the owner from setting a large callback limit to prevent orders from being placed.
     * @dev Emits the `CallbackGasLimitSet()` event.
     * @param newCallbackGasLimit The callback gas limit to provide for all orders.
     */
    function _setCallbackGasLimit(uint256 newCallbackGasLimit) internal {
        require(
            newCallbackGasLimit <= Limits.MAXIMUM_CALLBACK_GAS_LIMIT,
            GmxFrfStrategyErrors
                .CANNOT_SET_THE_CALLBACK_GAS_LIMIT_ABOVE_THE_MAXIMUM
        );
        callbackGasLimit_ = newCallbackGasLimit;
        emit CallbackGasLimitSet(newCallbackGasLimit);
    }

    /**
     * @notice Set the execution fee buffer percentage for the strategy. This is the percentage of the initially
     * calculated execution fee that needs to be provided additionally to prevent orders from failing execution.
     * The value of the execution fee buffer percentage should account for possible shifts in gas price between
     * order creation and keeper execution. A higher value will result in a higher execution fee being required
     * by the user. As such, a configured maximum value is checked against when setting this configuration variable
     * to prevent the owner from setting a high fee that prevents accounts from creating orders.
     * @dev Emits the `ExecutionFeeBufferPercentSet()` event.
     * @param newExecutionFeeBufferPercent The new execution fee buffer percentage.
     */
    function _setExecutionFeeBufferPercent(
        uint256 newExecutionFeeBufferPercent
    ) internal {
        require(
            newExecutionFeeBufferPercent <=
                Limits.MAXIMUM_EXECUTION_FEE_BUFFER_PERCENT,
            GmxFrfStrategyErrors
                .CANNOT_SET_THE_EXECUTION_FEE_BUFFER_ABOVE_THE_MAXIMUM
        );
        executionFeeBufferPercent_ = newExecutionFeeBufferPercent;
        emit ExecutionFeeBufferPercentSet(newExecutionFeeBufferPercent);
    }

    /**
     * @notice Set the referral code to use for all orders.
     * @dev Emits the `ReferralCodeSet()` event.
     * @param newReferralCode The new referral code to use for all orders.
     */
    function _setReferralCode(bytes32 newReferralCode) internal {
        referralCode_ = newReferralCode;
        emit ReferralCodeSet(newReferralCode);
    }

    /**
     * @notice Set the ui fee receiver to use for all orders.
     * @dev Emits the `UiFeeReceiverSet()` event.
     * @param newUiFeeReceiver The new ui fee receiver to use for all orders.
     */
    function _setUiFeeReceiver(address newUiFeeReceiver) internal {
        require(
            newUiFeeReceiver != address(0),
            GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );

        uiFeeReceiver_ = newUiFeeReceiver;
        emit UiFeeReceiverSet(newUiFeeReceiver);
    }

    /**
     * @notice Sets the withdrawal buffer percentage. There is a configured minimum to prevent the owner from allowing accounts
     * to withdraw funds that bring the account's value below the loan. There is no maximum because it may be neccesary in
     * extreme circumstances for the owner to disable withdrawals while a loan is active by setting a higher limit.
     * It is always possible to withdraw funds once the loan is repaid, so this does not lock user funds permanantly.
     * A `withdrawalBufferPercentage` of 1.1e18 (110%) implies that the value of an account after withdrawing funds
     * must be greater than the `1.1 * loan` for a given account.
     * @dev Emits the `WithdrawalBufferPercentageSet()` event.
     * @param newWithdrawalBufferPercentage The new withdrawal buffer percentage.
     */
    function _setWithdrawalBufferPercentage(
        uint256 newWithdrawalBufferPercentage
    ) internal {
        require(
            newWithdrawalBufferPercentage >=
                Limits.MINIMUM_WITHDRAWAL_BUFFER_PERCENT,
            GmxFrfStrategyErrors
                .WITHDRAWAL_BUFFER_PERCENTAGE_MUST_BE_GREATER_THAN_THE_MINIMUM
        );
        withdrawalBufferPercentage_ = newWithdrawalBufferPercentage;
        emit WithdrawalBufferPercentageSet(newWithdrawalBufferPercentage);
    }

    // ============ Private Functions ============

    /**
     * @notice Validate order pricing parameters, making sure parameters are internally consistent,
     * i.e. minimum order size does not exceed maximum.
     *  @param orderPricingParameters The order pricing parameters being validated.
     */
    function _validateOrderPricingParameters(
        OrderPricingParameters memory orderPricingParameters
    ) private pure {
        // It is important to note that no `decreaseDisabled` parameter is present. This is because
        // the owner of the GmxFrFStrategyManager contract should never be able to prevent accounts from closing positions.
        // However, in the event the market is either compromised or being winded down, it may be neccesary to disable increase orders
        // to mitigate protocol risk.

        // The `maxSwapSlippagePercent` must be validated to ensure the configured value is not too low such that it prevents any swaps from being executed.
        // Otherwise, the owner can effectively prevent all orders from being executed.
        require(
            orderPricingParameters.maxSwapSlippagePercent >=
                Limits.MINIMUM_MAX_SWAP_SLIPPAGE_PERCENT,
            GmxFrfStrategyErrors
                .CANNOT_SET_MAX_SWAP_SLIPPAGE_BELOW_MINIMUM_VALUE
        );

        // Similarly, the `maxPositionSlippagePercent` needs to be validated to prevent the owner from setting the number so low that
        // it prevents position decreases.
        require(
            orderPricingParameters.maxPositionSlippagePercent >=
                Limits.MINIMUM_MAX_POSITION_SLIPPAGE_PERCENT,
            GmxFrfStrategyErrors
                .CANNOT_SET_MAX_POSITION_SLIPPAGE_BELOW_MINIMUM_VALUE
        );

        // It is not possible for the owner of the contract to manipulate these configured parameters
        // to make it impossible to close a position, because the order logic itself when winding down a
        // position disregards order minimums if the position is being fully closed.
        require(
            orderPricingParameters.minOrderSizeUsd <=
                orderPricingParameters.maxOrderSizeUsd,
            GmxFrfStrategyErrors
                .MARKET_CONFIGURATION_MANAGER_MIN_ORDER_SIZE_MUST_BE_LESS_THAN_OR_EQUAL_TO_MAX_ORDER_SIZE
        );
    }

    /**
     * @notice Validate position parameters, making sure parameters are internally consistent,
     * i.e. minimum position size does not exceed maximum.
     * @param positionParameters The position parameters being validated.
     */
    function _validatePositionParameters(
        PositionParameters memory positionParameters
    ) private pure {
        require(
            positionParameters.minPositionSizeUsd <=
                positionParameters.maxPositionSizeUsd,
            GmxFrfStrategyErrors
                .MARKET_CONFIGURATION_MANAGER_MIN_POSITION_SIZE_MUST_BE_LESS_THAN_OR_EQUAL_TO_MAX_POSITION_SIZE
        );
    }

    /**
     * @notice Validate unwind parameters, making sure the owner of the contract cannot forcibly prevent and/or force liquidations.
     * @param unwindParameters The unwind parameters to validate.
     */
    function _validateUnwindParameters(
        UnwindParameters memory unwindParameters
    ) private pure {
        // The `minSwapRebalanceSize` does not need to be validated, because it's configured value becomes 'more extreme'
        // as it approaches 0, which is an acceptable value. Furthermore, this number represents a fixed token amount,
        // which varies depending on token decimals.

        // The `maxDeltaProportion` must be validated to prevent the owner of the contract from reducing the value and
        // profiting from rebalancing accounts. Furthermore, the number must be greater than 1 to function properly.
        require(
            unwindParameters.maxDeltaProportion >=
                Limits.MINIMUM_MAX_DELTA_PROPORTION_PERCENT,
            GmxFrfStrategyErrors
                .MAX_DELTA_PROPORTION_IS_BELOW_THE_MINIMUM_REQUIRED_VALUE
        );

        // The `maxPositionLeverage` must be validated to ensure the owner of the `GmxFrfManager` contract does not set a small configured value, as this can
        // allow positions to be releveraged unexpectedly, resulting in fees. Furthermore, if this number is too high, it puts positions at risk of
        // liquidation on GMX.
        require(
            unwindParameters.maxPositionLeverage >=
                Limits.MINIMUM_MAX_POSITION_LEVERAGE_PERCENT,
            GmxFrfStrategyErrors
                .MAX_POSITION_LEVERAGE_IS_BELOW_THE_MINIMUM_REQUIRED_VALUE
        );

        // The `unwindFee` must be validated so that the owner cannot forcibly take a sizeable portion of a position's value.
        require(
            unwindParameters.unwindFee <= Limits.MAXIMUM_UNWIND_FEE_PERCENT,
            GmxFrfStrategyErrors.UNWIND_FEE_IS_ABOVE_THE_MAXIMUM_ALLOWED_VALUE
        );
    }
}

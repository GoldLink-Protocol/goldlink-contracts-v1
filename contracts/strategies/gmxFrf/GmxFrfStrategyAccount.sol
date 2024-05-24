// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { StrategyAccount } from "../../core/StrategyAccount.sol";
import { IStrategyBank } from "../../interfaces/IStrategyBank.sol";
import { StrategyBankHelpers } from "../../libraries/StrategyBankHelpers.sol";
import { IStrategyController } from "../../interfaces/IStrategyController.sol";
import { IStrategyAccount } from "../../interfaces/IStrategyAccount.sol";
import {
    IGmxFrfStrategyManager
} from "./interfaces/IGmxFrfStrategyManager.sol";
import {
    IGmxFrfStrategyAccount
} from "./interfaces/IGmxFrfStrategyAccount.sol";
import {
    IGmxV2OrderTypes
} from "../../lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import { GmxFrfStrategyErrors } from "./GmxFrfStrategyErrors.sol";
import {
    IGmxV2OrderCallbackReceiver
} from "../../lib/gmx/interfaces/external/IGmxV2OrderCallbackReceiver.sol";
import {
    IGmxV2RoleStore
} from "../../strategies/gmxFrf/interfaces/gmx/IGmxV2RoleStore.sol";
import {
    IGmxV2EventUtilsTypes
} from "../../lib/gmx/interfaces/external/IGmxV2EventUtilsTypes.sol";
import { Role } from "../../lib/gmx/role/Role.sol";
import { GmxStrategyStorage } from "./impl/GmxStrategyStorage.sol";
import { AccountGetters } from "./libraries/AccountGetters.sol";
import { LiquidationLogic } from "./libraries/LiquidationLogic.sol";
import { MulticallChecks } from "./libraries/MulticallChecks.sol";
import { SwapCallbackLogic } from "./libraries/SwapCallbackLogic.sol";
import { OrderLogic } from "./libraries/OrderLogic.sol";
import { ClaimLogic } from "./libraries/ClaimLogic.sol";
import { WithdrawalLogic } from "./libraries/WithdrawalLogic.sol";

/**
 * @title GmxFrfStrategyAccount
 * @author GoldLink
 *
 * @notice Contract that enables strategies to interact with UniswapV3 pools.
 */
contract GmxFrfStrategyAccount is
    StrategyAccount,
    GmxStrategyStorage,
    IGmxFrfStrategyAccount
{
    // ============ Modifiers ============

    /// @notice Verify the market has been approved by this contract.
    modifier onlyApprovedMarket(address market) {
        _onlyApprovedMarket(market);
        _;
    }

    /// @notice Verify `msg.sender` has the controller role.
    modifier onlyControllerRole() {
        _onlyControllerRole();
        _;
    }

    /// @notice Ensure that `msg.value` is greater than or equal to the provided execution fee.
    /// This will not properly validate functions called via multicall, so additional logic must be used.
    modifier canPayFee(uint256 fee) {
        require(
            fee <= msg.value,
            GmxFrfStrategyErrors.MSG_VALUE_LESS_THAN_PROVIDED_EXECUTION_FEE
        );
        _;
    }

    /// @dev Require address is not zero.
    modifier onlyNonZeroAddress(address addressToCheck) {
        _onlyNonZeroAddress(addressToCheck);
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Constructor for upgradeable contract, distinct from initializer.
     *
     *  The constructor is used to set immutable variables, and for top-level upgradeable
     *  contracts, it is also used to disable the initializer of the logic contract.
     *
     *  Note that since this contract is used with beacon proxies, the immutable variables will
     *  be constant across all proxies pointing to the same beacon.
     */
    constructor(IGmxFrfStrategyManager manager) GmxStrategyStorage(manager) {
        _disableInitializers();
    }

    // ============ Initializer ============

    function initialize(
        address owner,
        IStrategyController strategyController
    )
        external
        initializer
        onlyNonZeroAddress(owner)
        onlyNonZeroAddress(address(strategyController))
    {
        __StrategyAccount_init(owner, strategyController);

        // Set isInMultiCall to the base state (1).
        isInMulticall_ = 1;
    }

    // ============ External Functions ============

    /**
     * @notice The recieve function is used to relay the execution fee refund to the address that paid the fee in the first place.
     * This is necessary because GMX does not yet support a callback function that pays the execution fee. and provides the assoicated order id.
     * Currently GMX allows 50k gas for native transfers, which is more than enough to execute this logic. If the transfer from this contract reverts,
     * the native token is wrapped by GMX and sent back to the account, where is serves as a donation.
     */
    receive() external payable {
        bytes32 toProcess = processingOrderId_;

        address feeRefundRecipient = orderIdToExecutionFeeRefundRecipient_[
            processingOrderId_
        ];

        // This is done as a convenience for anyone who accidentally sends native tokens to this contract. Receiving native tokens is not a security risk and no internal
        // accounting references the native balance, implying that patterns used to forcibly increment the native balance (such as self-destruct sends) do not create security concerns.
        require(
            feeRefundRecipient != address(0),
            GmxFrfStrategyErrors.ORDER_MANAGEMENT_INVALID_FEE_REFUND_RECIPIENT
        );

        delete orderIdToExecutionFeeRefundRecipient_[toProcess];

        delete processingOrderId_;

        // In the event that the transfer reverts, the `processingOrderId_` and `orderIdToExecutionFeeRefundRecipient_[processingOrderId_]` will remain stored in the contract permanently.
        // Furthermore, the creator of the order (either the account owner, a liquidator, or a rebalancer) will not receive the execution fee refund.
        // Instead, the GMX behavior for transferring the execution fee refund is used to turn the unreturnable fee into an account donation, as
        // execution fee transfers that revert are sent in the wrapped native token instead. This effectively acts as a donation to the account, because
        // while the native token is not considered an asset, and never can be, the wrapped native can (and likely will, depending on the market configuration).

        // The Related GMX fee-refund logic can be found here:
        // Execution Fee Refunds: https://github.com/gmx-io/gmx-synthetics/blob/178290846694d65296a14b9f4b6ff9beae28a7f7/contracts/gas/GasUtils.sol#L130-L132
        // Native Transfer Logic: https://github.com/gmx-io/gmx-synthetics/blob/178290846694d65296a14b9f4b6ff9beae28a7f7/contracts/token/TokenUtils.sol#L98-L133

        // Since every GMX `orderId` is unique, there is not a risk of the refund being sent to the wrong address, since GMX will always first call the callback function,
        // where the existing `processingOrderId_` will be overwritten, so when the refund is sent, it will be routed to the correct address. The two possible cases are the case where
        // the transfer reverts, and the case where the transfer is successful.

        // The flow for the successful case is as follows:
        // 1. Callback function (either `afterOrderExecution` or `afterOrderCancellation`) is called, and the `processingOrderId_` is set to the order being executed.
        // 2. The receive function is called, and the `orderIdToExecutionFeeRefundRecipient_[processingOrderId_]` is used to pay out the fee successfully to the receiver.
        //    Both the `processingOrderId_` and `orderIdToExecutionFeeRefundRecipient_[processingOrderId_]` are deleted.
        // 3. The next order is executed, and then either of the two cases occurs.

        // The flow for the failed case is as follows:
        // 1. Callback Function (either `afterOrderExecution` or `afterOrderCancellation`) is called, and the `processingOrderId_` is set to the order being executed.
        // 2. The receive function is called, and the `orderIdToExecutionFeeRefundRecipient_[processingOrderId_]` is used to pay out the fee unsuccessfully to the receiver.
        // 3. In the event receive() is called before a new order is executed, both `processingOrderId_` and `orderIdToExecutionFeeRefundRecipient_[processingOrderId_]` will be deleted, and
        // the value of the native token will be sent to the `executionFeeRecipient_`. It is made clear that native tokens should not be directly transferred to this contract, and is on the
        // individual to ensure that the correct token is sent to the contract.
        // 4. Otherwise, one of the callback functions is called, `processingOrderId_` is set to the new order, and then either of the two cases occurs.

        payable(feeRefundRecipient).transfer(msg.value);
    }

    /**
     * @notice Sends an increase order request to GMX in the provided `market` using `collateralAmount` as the initial order funds.
     * The `market` must be an approved strategy market. The order will be executed at the current market price as per the GMX protocol, with slippage protection
     * based on the current chainlink oracle price. The order must abide by the configuration for this specific market, which limits order size.
     * Furthermore, if a position already exists in this market, the order will set increase amounts for this position so that the position is delta neutral,
     * which takes into account accrued but not yet settled negative funding and borrow fees. Only one open order per market is allowed at a time. Cannot be called if there are pending orders in this market.
     * @dev Emits the `CreateIncreaseOrder()` event.
     * @param market           The market to send the order to.
     * @param collateralAmount The amount of collateral (USDC) to use for the order.
     * @return order           The order that was created via GMX. This includes all information related to order price, size, acceptable prices and expected collateral amounts.
     * @return orderKey        The unique identifier for the order.
     */
    function executeCreateIncreaseOrder(
        address market,
        uint256 collateralAmount,
        uint256 executionFee
    )
        external
        payable
        onlyOwner
        strategyNonReentrant
        whenNotLiquidating
        hasActiveLoan
        onlyApprovedMarket(market)
        canPayFee(executionFee)
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        )
    {
        // Create the increase order, which sends both the execution fee and initial collateral to GMX. Will create an order that tries to satisfy the neutrality of
        // the position, which includes accounting for accrued but not yet settled negative funding and borrow fees.
        (order, orderKey) = OrderLogic.createIncreaseOrder(
            MANAGER,
            orderIdToExecutionFeeRefundRecipient_,
            market,
            collateralAmount,
            executionFee
        );

        emit CreateIncreaseOrder(market, order, orderKey);

        return (order, orderKey);
    }

    /**
     * @notice Sends an decrease order request to GMX in the provided `market`. The order will be executed at the current market price based on GMX's internal oracle.
     * The `sizeDeltaUsd` is the amount of open interest to reduce the position by in USD. `SizeDeltaUsd` should be less than or equal to the current position's
     * `sizeInUsd`. The order must abide by the configuration for this specific market, which limits order size and remaining position size.
     * Only one open order per market is allowed at a time. Cannot be called if there are pending orders in this market.
     * @dev Emits the `CreateDecreaseOrder()` event.
     * @param market       The market to send the order to.
     * @param sizeDeltaUsd The size of the position to reduce by in USD.
     * @return order       The order that was created via GMX. This includes all information related to order price, size, acceptable prices
     *                     and expected output funds.
     * @return orderKey    The unique identifier for the order.
     */
    function executeCreateDecreaseOrder(
        address market,
        uint256 sizeDeltaUsd,
        uint256 executionFee
    )
        external
        payable
        onlyOwner
        strategyNonReentrant
        whenNotLiquidating
        hasActiveLoan
        onlyApprovedMarket(market)
        canPayFee(executionFee)
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        )
    {
        // Create the decrease order, which sends the execution fee to the GMX router to pay for keeper costs. The execution fee refund will be
        // sent back to the order creator at the time of keeper execution.
        (order, orderKey) = OrderLogic.createDecreaseOrder(
            MANAGER,
            orderIdToExecutionFeeRefundRecipient_,
            market,
            sizeDeltaUsd,
            executionFee
        );

        emit CreateDecreaseOrder(market, order, orderKey);

        return (order, orderKey);
    }

    /**
     * @notice Cancels an open order in the provided `market` with the given `orderKey`. Reverts if the order does not exist or the order is for either a liquidation or rebalance.
     * @dev Emits the `CancelOrder()` event.
     * @param orderKey The unique identifier for the order to cancel.
     */
    function executeCancelOrder(
        bytes32 orderKey
    ) external onlyOwner strategyNonReentrant whenNotLiquidating hasActiveLoan {
        OrderLogic.cancelOrder(MANAGER, pendingLiquidations_, orderKey);

        emit CancelOrder(orderKey);
    }

    /**
     * @notice Claims funding fees for the provided `markets` and `assets`. This includes both unclaimed funding fees and unclaimed collateral. Claimed funding fees are deposited into the account
     * and remain there until the loan is paid off or the tokens are sold.
     * @param markets The markets to claim funding fees for. Must be aligned with the `assets` array and they must be of equal length.
     * @param assets  The assets to claim funding fees for. Must be aligned with the `markets` array and they must be of equal length.
     */
    function executeClaimFundingFees(
        address[] memory markets,
        address[] memory assets
    ) external strategyNonReentrant {
        uint256 marketLength = markets.length;
        for (uint256 i = 0; i < marketLength; i++) {
            _onlyApprovedMarket(markets[i]);
        }

        uint256[] memory claimedAmounts = ClaimLogic.claimFundingFees(
            MANAGER,
            markets,
            assets
        );

        emit ClaimFundingFees(markets, assets, claimedAmounts);
    }

    /**
     * @notice Withdraws profit from the strategy account. Profit can only be withdrawn if the value of the account after withdrawing
     * assets is greater than `loan * withdrawalBufferPercentage`. Furthermore, assets in a given market can only be withdrawn if
     * removing these assets brings the market delta closer to neutral. This inherently implies that you can only withdraw tokens from
     * markets that have more long tokens than short.
     * @dev Emits the `WithdrawProfit()` event.
     * @param params Struct with information about the market, amount and recipient of the withdrawn assets.
     */
    function executeWithdrawProfit(
        WithdrawalLogic.WithdrawProfitParams memory params
    )
        external
        onlyOwner
        strategyNonReentrant
        whenNotLiquidating
        hasActiveLoan
        onlyApprovedMarket(params.market)
    {
        WithdrawalLogic.withdrawProfit(
            MANAGER,
            STRATEGY_BANK(),
            address(this),
            params
        );

        emit WithdrawProfit(params.market, params.recipient, params.amount);
    }

    /**
     * @notice Allows the owner of the Strategy Account to sell off assets. This allows account owners to
     * obtain USDC in order to repay their loan. Note: In times of high volatility, the configured `maxSwapSlippage` may result
     * in it being impossible to atomically swap for the required amount of `USDC`.
     * @dev Emits the `SwapAssets()` event.
     * @param market             The market to swap assets in.
     * @param longTokenAmountOut The amount of `asset` to swap for USDC.
     * @param callback           The address of the callback contract that implements `ISwapCallbackHandler.handleSwapCallback`.
     * @param receiver           The address to send `asset` to before executing the callback function.
     * @param data               Data passed through to the callback contract.
     */
    function executeSwapAssets(
        address market,
        uint256 longTokenAmountOut,
        address callback,
        address receiver,
        bytes memory data
    )
        external
        onlyOwner
        strategyNonReentrant
        whenNotLiquidating
        hasActiveLoan
        onlyApprovedMarket(market)
    {
        // Swap the `longToken` balance associated with `market` for USDC.
        // There is a small slipapge allowance from the Chainlink Oracle Price (which is computed as `asset` / USDC)
        // to account for dex mispricings / dex slippage. It is expected that the worst case always occurs (the least allowable
        // amount given the slippage tolerance) is returned, since it is in the best interest of the account owner to take whatever
        // extra they can get for themselves.
        uint256 usdcAmountIn = WithdrawalLogic.swapTokensForUSDC(
            MANAGER,
            market,
            address(this),
            longTokenAmountOut,
            callback,
            receiver,
            data
        );

        emit SwapAssets(market, longTokenAmountOut, usdcAmountIn);
    }

    /**
     * @notice  Claims collateral in the event an account's collateral is held in escrow due to a high price impact swap. While the configuration of each market should prevent this, this method
     * is a saftey measure in the event that a high price impact swap occurs and the account is liquidated before the collateral can be claimed. In the event this occurs, if the timeKey provided falls
     * before the `lastLiquidationTimestamp_` for the account, the claimed funds are sent to the trusted liquidator to ensure the account owner has paid back all lost funds to lenders.
     * @param market   The market to claim collateral in.
     * @param asset    The collateral asset to claim.
     * @param timeKey  The time key of the claim.
     */
    function executeClaimCollateral(
        address market,
        address asset,
        uint256 timeKey
    ) external strategyNonReentrant onlyApprovedMarket(market) {
        ClaimLogic.claimCollateral(
            MANAGER,
            market,
            asset,
            timeKey,
            lastLiquidationTimestamp_
        );

        emit ClaimCollateral(market, asset, timeKey);
    }

    /**
     * @notice Liquidates the specified `asset` in the amount of `amount` to the `receiever` address. Can only be called when the account has an active loan. The `callback` address must be
     * a contract that implements the `ISwapCallbackHandler` interface. The fee paid to the liquidator is reflected in the amount of expected USDC that is receieved.
     * @param asset     The asset to liquidate.
     * @param amount    The amount of the asset to liquidate.
     * @param callback  The address of the callback contract to call after the liquidation is complete.
     * @param receiever The address to send `asset` to before initiating the callback.
     * @param data      Data that is passed through to the callback contract.
     */
    function executeLiquidateAssets(
        address asset,
        uint256 amount,
        address callback,
        address receiever,
        bytes memory data
    ) external strategyNonReentrant whenLiquidating hasActiveLoan {
        uint256 usdcAmountIn = SwapCallbackLogic.handleSwapCallback(
            MANAGER,
            asset,
            amount,
            MANAGER.getAssetLiquidationFeePercent(asset),
            callback,
            receiever,
            data
        );

        emit LiquidateAssets(msg.sender, asset, amount, usdcAmountIn);
    }

    /**
     * @notice Liquidates a position in the specified `market` in the amount of `sizeDeltaUsd`. Can only be called when the account has an active loan.
     * The fee paid to the liquidator is reflected in the amount of expected USDC that is receieved.
     * @param market       The market containing the position to liquidate.
     * @param sizeDeltaUsd The size of the position to liquidate in USD.
     * @param executionFee The gas stipend for executing the transfer in the liquidation.
     * @return order       The liquidation order that was created via GMX.
     * @return orderKey    The key for the order.
     */
    function executeLiquidatePosition(
        address market,
        uint256 sizeDeltaUsd,
        uint256 executionFee
    )
        external
        payable
        strategyNonReentrant
        whenLiquidating
        hasActiveLoan
        canPayFee(executionFee)
        onlyApprovedMarket(market)
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        )
    {
        (order, orderKey) = LiquidationLogic.liquidatePosition(
            MANAGER,
            orderIdToExecutionFeeRefundRecipient_,
            pendingLiquidations_,
            market,
            sizeDeltaUsd,
            executionFee
        );

        emit LiquidatePosition(msg.sender, market, order, orderKey);

        return (order, orderKey);
    }

    /**
     * @notice Releverage a position that is out of balance. The position's current leverage must be above the configured `maxPositionLeverage` for the market.
     * @dev Emits the `ReleveragePosition()` event.
     * @param market       The market to releverage the position in.
     * @param sizeDeltaUsd The `sizeDeltaUsd` of the liquidation order. This represents the reduction in the size of the short position on GMX. Must comply with
     * the configured `minOrderSize` and `maxOrderSize`. Furthermore, the position after creating the decrease order must abide by the `minimumPositionSize`.
     * @param executionFee The gas stipend for executing the transfer in the liquidation.
     * @return order       The liquidation order that was created via GMX.
     * @return orderKey    The key for the order.
     */
    function executeReleveragePosition(
        address market,
        uint256 sizeDeltaUsd,
        uint256 executionFee
    )
        external
        payable
        strategyNonReentrant
        whenNotLiquidating
        hasActiveLoan
        canPayFee(executionFee)
        onlyApprovedMarket(market)
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        )
    {
        (order, orderKey) = LiquidationLogic.releveragePosition(
            MANAGER,
            orderIdToExecutionFeeRefundRecipient_,
            pendingLiquidations_,
            market,
            sizeDeltaUsd,
            executionFee
        );

        emit ReleveragePosition(msg.sender, market, order, orderKey);

        return (order, orderKey);
    }

    /**
     * @notice Rebalances the position in the specified `market` to maintain delta neutrality. Can only be called if delta in the specified `market` is above the configured
     * threshold. The callback logic is the exact same as `executeLiquidateAssets`, however the amount of assets that can be liquidated is constrained by the
     * position's delta.
     * @dev Emits the `SwapRebalancePosition()` event.
     * @param market         The market to rebalance the position in.
     * @param callbackConfig The configuration for the callback contract to call after the rebalance is complete.
     */
    function executeSwapRebalance(
        address market,
        IGmxFrfStrategyAccount.CallbackConfig memory callbackConfig,
        bytes memory data
    )
        external
        strategyNonReentrant
        whenNotLiquidating
        hasActiveLoan
        onlyApprovedMarket(market)
    {
        (uint256 rebalanceAmount, uint256 usdcAmountIn) = LiquidationLogic
            .swapRebalancePosition(
                MANAGER,
                pendingLiquidations_,
                market,
                callbackConfig,
                data
            );

        emit SwapRebalancePosition(
            msg.sender,
            market,
            rebalanceAmount,
            usdcAmountIn
        );
    }

    /**
     * @notice Rebalances the position in the specified `market` to maintain delta neutrality. Can only be called if the amount of assets for the specified `market` is below the configured
     * `minSwapRebalanceThreshold` for the market and the position's delta is above the configured `deltaRebalanceThreshold`. The `sizeDeltaUsd` is determined by the contract logic.
     * @dev Emits the `RebalancePosition()` event.
     * @param market    The market to rebalance the position in.
     * @return order    The rebalance order that was created via GMX.
     * @return orderKey The key for the order.
     */
    function executeRebalancePosition(
        address market,
        uint256 executionFee
    )
        external
        payable
        strategyNonReentrant
        whenNotLiquidating
        hasActiveLoan
        canPayFee(executionFee)
        onlyApprovedMarket(market)
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        )
    {
        // Need to make sure that it is impossible to send tokens to the account to force the position to be rebalanced.
        // We cannot simply prohibit being able to sell tokens when rebalancing, because it is possible for the GMX swap to fail when decreasing a position, resulting in both collateral tokens
        // (tokens with non-zero delta) and USDC. In the event this occurs, we need to be able to rebalance the position by selling the excess collateral tokens.

        // First of all, we need to determine if the delta is positive (more long than short) or negative (more short than long).

        // In the event the position is too positive, we can sell tokens to get back to the threshold. The delta being too positive can happen in three possible ways:
        // 1) When entering the position, the price impact or spread is in our favor, resulting in the position's collateral being greater than the size of the short.
        // 2) When the position is decreased, the collateral swap fails, resulting in the swap output containing both collateral tokens and USDC. This case is unlikely, but in the event it occurs,
        // is the most likely situation to result in a highly positive delta.
        // 3) Funding fees accrue over time, resulting in a slow increase in position delta.

        // Case 2) and Case 3) are more likely to cause positive delta. In these cases, the best option is to sell the minimum amount of tokens to get back to the threshold.

        // Case 1) is unlikely to cause significant positive delta. However, this is the only case in which the collateral may have to be decreased in order to maintain neutrality. This should be the last
        // resort.

        // In the event the position is too negative, this implies that the position is too short. This can happen in two possible ways:
        // 1) When modifying a position, whether increasing or decreasing, the price impact or spread favors the short, resulting in the position's collateral being less than the size of the long.
        // 2) The accrual of negative funding and borrowing fees over time, resulting in a slow decrease in position delta.

        (order, orderKey) = LiquidationLogic.rebalancePosition(
            MANAGER,
            orderIdToExecutionFeeRefundRecipient_,
            pendingLiquidations_,
            market,
            executionFee
        );

        emit RebalancePosition(msg.sender, market, order, orderKey);

        return (order, orderKey);
    }

    /**
     * @notice Multicall method for performing complex multistep actions while preserving the caller context.
     * @param data     Encoded calldata to execute. Must reference an available method.
     * @return results Return values for each encoded call in the same order as the calls specified in `data`.
     */
    function multicall(
        bytes[] calldata data
    ) public payable returns (bytes[] memory results) {
        // Check that this is not a nested multicall.
        require(
            isInMulticall_ == 1,
            GmxFrfStrategyErrors.NESTED_MULTICALLS_ARE_NOT_ALLOWED
        );

        // Write to storage that we are currently executing a multicall to prevent nested multicalls.
        isInMulticall_ = 2;

        // Get the starting balance of the contract, excluding the native token sent with the call. The contract
        // balance at the end of the transaction should never be below this. It is important to note that any method
        // that withdraws native token can not be used in the multicall method. Since this only includes the function
        // `withdrawNativeAsset()`, and this contract is not intended to hold native tokens, this is not a severe limitation.

        // This allows us to pass the execution fee in as a parameter and call multiple GMX functions that require a gas stipend
        // in a single multicall transaction without risking the caller being able to spend part of the contract's balance.
        uint256 minBalance = address(this).balance - msg.value;

        results = new bytes[](data.length);
        uint256 dataLength = data.length;
        for (uint256 i = 0; i < dataLength; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(
                data[i]
            );

            MulticallChecks.checkMulticallResult(success, result);

            results[i] = result;
        }

        // Ensure that native token was not spent in excess of msg.value.
        require(
            address(this).balance >= minBalance,
            GmxFrfStrategyErrors
                .TOO_MUCH_NATIVE_TOKEN_SPENT_IN_MULTICALL_EXECUTION
        );

        // Reset the `isInMulticall` state to 1.
        isInMulticall_ = 1;
    }

    /**
     * @notice Called after order execution.
     * @dev Emits the `OrderExecuted()` event.
     * @param key   The key of the order.
     * @param order The order that was executed.
     */
    function afterOrderExecution(
        bytes32 key,
        IGmxV2OrderTypes.Props memory order,
        IGmxV2EventUtilsTypes.EventLogData memory eventData
    ) external onlyControllerRole {
        OrderLogic.afterOrderExecution(
            MANAGER,
            pendingLiquidations_,
            key,
            order,
            eventData
        );

        processingOrderId_ = key;

        emit OrderExecuted(key);
    }

    /**
     * @notice Called after an order cancellation.
     * @dev Emits the `OrderCancelled()` event.
     * @param key       The key of the order.
     * @param order     The order that was cancelled.
     * @param eventData The event data for the cancellation of the order.
     */
    function afterOrderCancellation(
        bytes32 key,
        IGmxV2OrderTypes.Props memory order,
        IGmxV2EventUtilsTypes.EventLogData memory eventData
    ) external onlyControllerRole {
        OrderLogic.afterOrderCancellation(
            pendingLiquidations_,
            key,
            order,
            eventData
        );

        processingOrderId_ = key;

        emit OrderCancelled(key);
    }

    // ============ Public Functions ============

    /**
     * @notice Get the total value of the account in terms of the `strategyAsset`.
     * @return strategyAssetValue The value of a position in terms of USDC.
     */
    function getAccountValue()
        public
        view
        override(StrategyAccount, IGmxFrfStrategyAccount)
        returns (uint256 strategyAssetValue)
    {
        return AccountGetters.getAccountValueUsdc(MANAGER, address(this));
    }

    // ============ Internal Functions ============

    /**
     * @notice Implements is liquidation finished, validating:
     * 1. There are no pending orders for the account.
     * 2. There are no open positions for the account.
     * 3. There are no unclaimed funding fees for the acocunt.
     * 4. The long token balance of this account is below the dust threshold for the market.
     * @return finished If the liquidation is finished and the `StrategyBank` can now execute
     * the liquidation, returning funds to lenders.
     */
    function _isLiquidationFinished()
        internal
        view
        override
        returns (bool finished)
    {
        return AccountGetters.isLiquidationFinished(MANAGER, address(this));
    }

    /**
     * @notice Returns the asset amount available that the strategy can pay off
     *  a liquidation with. In this the case of the GMX Funding Rate Farming Strategy,
     *  it is simply the balance of USDC in the contract.
     */
    function _getAvailableStrategyAsset()
        internal
        view
        override
        returns (uint256)
    {
        return MANAGER.USDC().balanceOf(address(this));
    }

    function _onlyApprovedMarket(address market) internal view {
        require(
            MANAGER.isApprovedMarket(market),
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
    }

    function _onlyControllerRole() internal view {
        require(
            MANAGER.gmxV2RoleStore().hasRole(msg.sender, Role.CONTROLLER),
            GmxFrfStrategyErrors
                .GMX_FRF_STRATEGY_ORDER_CALLBACK_RECEIVER_CALLER_MUST_HAVE_CONTROLLER_ROLE
        );
    }

    /**
     * @notice After process liquidation hook to set the most recent liquidation timestamp.
     */
    function _afterProcessLiquidation(uint256) internal override {
        lastLiquidationTimestamp_ = block.timestamp;
    }
}

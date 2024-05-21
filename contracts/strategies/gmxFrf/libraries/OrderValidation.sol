// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IGmxV2DataStore
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2OrderTypes
} from "../../../lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import { GasUtils } from "../../../lib/gmx/gas/GasUtils.sol";
import { OrderStoreUtils } from "../../../lib/gmx/order/OrderStoreUtils.sol";
import {
    PositionStoreUtils
} from "../../../lib/gmx/position/PositionStoreUtils.sol";
import {
    GmxMarketGetters
} from "../../../strategies/gmxFrf/libraries/GmxMarketGetters.sol";
import { PercentMath } from "../../../libraries/PercentMath.sol";
import { GmxFrfStrategyErrors } from "../GmxFrfStrategyErrors.sol";

/**
 * @title OrderValidation
 * @author GoldLink
 *
 * @dev Library for validating new orders.
 */
library OrderValidation {
    using PercentMath for uint256;

    // ============ Internal Functions ============

    /**
     * @notice Validate that an account `address(this)` has no pending orders for a market.
     * @param dataStore The data store that pending orders would be registered in.
     * @param market    The market pending orders are being checked in.
     */
    function validateNoPendingOrdersInMarket(
        IGmxV2DataStore dataStore,
        address market
    ) internal view {
        bytes32[] memory orderKeys = OrderStoreUtils.getAccountOrderKeys(
            dataStore,
            address(this)
        );

        uint256 orderKeysLength = orderKeys.length;
        for (uint256 i = 0; i < orderKeysLength; ++i) {
            address orderMarket = OrderStoreUtils.getOrderMarket(
                dataStore,
                orderKeys[i]
            );

            require(
                orderMarket != market,
                GmxFrfStrategyErrors.ORDER_VALIDATION_MARKET_HAS_PENDING_ORDERS
            );
        }
    }

    /**
     * @notice Validate the provided execution fee will cover the minimum fee for the execution.
     * @param dataStore                    The data store storage information relevant to the transaction
     * is being queried from.
     * @param orderType                    The type of order being placed.
     * @param swapPathLength               The length of the swap path.
     * @param callbackGasLimit             The gas limit on the callback for the transaction.
     * @param executionFeeBufferPercentage The buffer on the minimum provided limit to account for
     * a higher execution fee than expected.
     * @param gasPrice                     The gas price multiplier for the gas limit with buffer.
     * @param providedExecutionFee         The execution fee provided for the transaction.
     */
    function validateExecutionFee(
        IGmxV2DataStore dataStore,
        IGmxV2OrderTypes.OrderType orderType,
        uint256 swapPathLength,
        uint256 callbackGasLimit,
        uint256 executionFeeBufferPercentage,
        uint256 gasPrice,
        uint256 providedExecutionFee
    ) internal view {
        // Estimate gas limit for order type.
        uint256 calculatedGasLimit;
        if (orderType == IGmxV2OrderTypes.OrderType.MarketIncrease) {
            calculatedGasLimit = GasUtils.estimateExecuteIncreaseOrderGasLimit(
                dataStore,
                swapPathLength,
                callbackGasLimit
            );
        } else if (orderType == IGmxV2OrderTypes.OrderType.MarketDecrease) {
            calculatedGasLimit = GasUtils.estimateExecuteDecreaseOrderGasLimit(
                dataStore,
                swapPathLength,
                callbackGasLimit
            );
        } else {
            calculatedGasLimit = GasUtils.estimateExecuteSwapOrderGasLimit(
                dataStore,
                swapPathLength,
                callbackGasLimit
            );
        }

        // Get the minimum provided limit given the execution fee buffer.
        uint256 minimumProvidedLimit = calculatedGasLimit +
            calculatedGasLimit.percentToFraction(executionFeeBufferPercentage);

        // Get the fee for the provided limit.
        uint256 minimumProvidedFee = gasPrice * minimumProvidedLimit;

        require(
            providedExecutionFee >= minimumProvidedFee,
            GmxFrfStrategyErrors
                .ORDER_VALIDATION_PROVIDED_EXECUTION_FEE_IS_TOO_LOW
        );
    }

    /**
     * @notice Validate that an account `address(this)` has a position for a market.
     * @param dataStore The data store that position would be registered in.
     * @param market    The market the position is being checked in.
     */
    function validatePositionExists(
        IGmxV2DataStore dataStore,
        address market
    ) internal view {
        bytes32 key = PositionStoreUtils.getPositionKey(
            address(this),
            market,
            GmxMarketGetters.getLongToken(dataStore, market),
            false
        );
        uint256 positionSizeUsd = PositionStoreUtils.getPositionSizeUsd(
            dataStore,
            key
        );

        require(
            positionSizeUsd != 0,
            GmxFrfStrategyErrors.ORDER_VALIDATION_POSITION_DOES_NOT_EXIST
        );
    }

    /**
     * @notice Validate that the order type is enabled for the market.
     * @param ordersEnabled If the order type is enabled.
     */
    function validateOrdersEnabled(bool ordersEnabled) internal pure {
        require(
            ordersEnabled,
            GmxFrfStrategyErrors.ORDER_VALIDATION_ORDER_TYPE_IS_DISABLED
        );
    }

    /**
     * @notice Validate increase price is above minimum acceptable price.
     * @param executionPrice         The price that the order would be executed at.
     * @param minimumAcceptablePrice The minimum price allowed for executing the order.
     */
    function validateIncreaseOrderPrice(
        uint256 executionPrice,
        uint256 minimumAcceptablePrice
    ) internal pure {
        require(
            executionPrice >= minimumAcceptablePrice,
            GmxFrfStrategyErrors
                .ORDER_VALIDATION_EXECUTION_PRICE_NOT_WITHIN_SLIPPAGE_RANGE
        );
    }

    /**
     * @notice Validate decrease price is below minimum acceptable price.
     * @param executionPrice     The price that the order would be executed at.
     * @param maxAcceptablePrice The max price allowed for executing the order.
     */
    function validateDecreaseOrderPrice(
        uint256 executionPrice,
        uint256 maxAcceptablePrice
    ) internal pure {
        require(
            executionPrice <= maxAcceptablePrice,
            GmxFrfStrategyErrors
                .ORDER_VALIDATION_ACCEPTABLE_PRICE_IS_NOT_WITHIN_SLIPPAGE_BOUNDS
        );
    }

    /**
     * @notice Valide the order size is within the acceptable range for the market.
     * @param minOrderSizeUSD The minimum size in USD that the order can be.
     * @param maxOrderSizeUSD The max size in USD that the order can be.
     * @param orderSizeUSD    The size of the order in USD.
     */
    function validateOrderSize(
        uint256 minOrderSizeUSD,
        uint256 maxOrderSizeUSD,
        uint256 orderSizeUSD
    ) internal pure {
        require(
            orderSizeUSD >= minOrderSizeUSD,
            GmxFrfStrategyErrors.ORDER_VALIDATION_ORDER_SIZE_IS_TOO_SMALL
        );

        require(
            orderSizeUSD <= maxOrderSizeUSD,
            GmxFrfStrategyErrors.ORDER_VALIDATION_ORDER_SIZE_IS_TOO_LARGE
        );
    }

    /**
     * @notice Valide the position size is within the acceptable range for the market.
     * @param minPositionSizeUsd The minimum size in USD that the position can be.
     * @param maxPositionSizeUsd The max size in USD that the position can be.
     * @param positionSizeUsd    The size of the position in USD.
     */
    function validatePositionSize(
        uint256 minPositionSizeUsd,
        uint256 maxPositionSizeUsd,
        uint256 positionSizeUsd
    ) internal pure {
        require(
            positionSizeUsd == 0 || positionSizeUsd >= minPositionSizeUsd,
            GmxFrfStrategyErrors.ORDER_VALIDATION_POSITION_SIZE_IS_TOO_SMALL
        );

        require(
            positionSizeUsd <= maxPositionSizeUsd,
            GmxFrfStrategyErrors.ORDER_VALIDATION_POSITION_SIZE_IS_TOO_LARGE
        );
    }

    /**
     * @notice Validate the swap slippage, that the estimated output is greater than
     * or equal to the minimum output.
     * @param estimatedOutput The estimated output after swap slippage.
     * @param minimumOutput   The minimum output allowed after swap slippage.
     */
    function validateSwapSlippage(
        uint256 estimatedOutput,
        uint256 minimumOutput
    ) internal pure {
        require(
            estimatedOutput >= minimumOutput,
            GmxFrfStrategyErrors.ORDER_VALIDATION_SWAP_SLIPPAGE_IS_TOO_HGIH
        );
    }
}

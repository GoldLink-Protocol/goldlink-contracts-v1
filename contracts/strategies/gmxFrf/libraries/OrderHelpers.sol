// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    IGmxV2OrderTypes
} from "../../../lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import { PercentMath } from "../../../libraries/PercentMath.sol";

/**
 * @title OrderHelpers
 * @author GoldLink
 *
 * @dev Library for supporting order creation.
 */
library OrderHelpers {
    using PercentMath for uint256;

    // ============ Internal Functions ============

    /**
     * @notice Create a `CreateOrderParamsAddresses` struct encapsulating relevant
     * addresses for a newly created order.
     * @param market                      The market the order is for.
     * @param initialCollateralToken      The initial collateral token for the order.
     * @param uiFeeReceiver               The address of the UI fee receiver
     * @param includesSwap                The swap path if one exists for the order
     * @return createOrderAddressesObject The struct encapsulating all relevant addresses
     * for the newly created order.
     */
    function createOrderAddresses(
        address market,
        address initialCollateralToken,
        address uiFeeReceiver,
        bool includesSwap
    )
        internal
        view
        returns (
            IGmxV2OrderTypes.CreateOrderParamsAddresses
                memory createOrderAddressesObject
        )
    {
        address[] memory swapPath = new address[](0);
        if (includesSwap) {
            swapPath = new address[](1);
            swapPath[0] = market;
        }
        return
            IGmxV2OrderTypes.CreateOrderParamsAddresses({
                receiver: address(this),
                callbackContract: address(this),
                uiFeeReceiver: uiFeeReceiver,
                market: market,
                initialCollateralToken: initialCollateralToken,
                swapPath: swapPath
            });
    }

    /**
     * @notice Get the minimum assets from swapping after worst-case allowed slippage.
     * @param amount               The amount that would be received without any slippage.
     * @param maxSlippage          The maximum allowed slippage before the transaction would revert.
     * @return amountAfterSlippage The amount received after maximum slippage.
     */
    function getMinimumSwapOutputWithSlippage(
        uint256 amount,
        uint256 maxSlippage
    ) internal pure returns (uint256 amountAfterSlippage) {
        return amount - amount.percentToFraction(maxSlippage);
    }

    /**
     * @notice Get minimum acceptable price for increase given maximum slippage.
     * @param currentPrice            The current price for the market.
     * @param maxSlippage             The maximum slippage allowed.
     * @return minimumAcceptablePrice The minimum acceptable price after slippage.
     */
    function getMinimumAcceptablePriceForIncrease(
        uint256 currentPrice,
        uint256 maxSlippage
    ) internal pure returns (uint256 minimumAcceptablePrice) {
        return currentPrice - currentPrice.percentToFraction(maxSlippage);
    }

    /**
     * @notice Get maximum acceptable price for decrease given maximum slippage.
     * @param currentPrice            The current price for the market.
     * @param maxSlippage             The maximum slippage allowed.
     * @return maximumAcceptablePrice The maximum acceptable price after slippage.
     */
    function getMaximumAcceptablePriceForDecrease(
        uint256 currentPrice,
        uint256 maxSlippage
    ) internal pure returns (uint256 maximumAcceptablePrice) {
        return currentPrice + currentPrice.percentToFraction(maxSlippage);
    }
}

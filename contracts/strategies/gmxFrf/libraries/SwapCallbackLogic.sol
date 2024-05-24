// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { GmxFrfStrategyErrors } from "../GmxFrfStrategyErrors.sol";
import {
    IGmxFrfStrategyManager
} from "../interfaces/IGmxFrfStrategyManager.sol";
import { ISwapCallbackRelayer } from "../interfaces/ISwapCallbackRelayer.sol";
import { Pricing } from "./Pricing.sol";
import { PercentMath } from "../../../libraries/PercentMath.sol";

/**
 * @title SwapCallbackLogic
 * @author GoldLink
 * @dev Library for handling swap callback functions.
 */
library SwapCallbackLogic {
    using SafeERC20 for IERC20;
    using PercentMath for uint256;

    // ============ External Functions ============

    /**
     * @notice Handle the accounting for an atomic asset swap, used for selling off spot assets.
     * @param asset              The asset being swapped. If the asset does not have a valid oracle, the call will revert.
     * @param amount             The amount of `asset` that should be sent to the `tokenReciever`.
     * @param maxSlippagePercent The maximum slippage percent allowed during the callback's execution.
     * @param callback           The callback that will be called to handle the swap. This must implement the `ISwapCallbackHandler` interface and return the expected USDC amount
     * after execution finishes.
     * @param tokenReceiever    The address that should recieve the `asset` being swapped.
     * @param data              Data passed through to the callback contract.
     * @return usdcAmountIn     The amount of USDC received back after the callback.
     */
    function handleSwapCallback(
        IGmxFrfStrategyManager manager,
        address asset,
        uint256 amount,
        uint256 maxSlippagePercent,
        address callback,
        address tokenReceiever,
        bytes memory data
    ) public returns (uint256 usdcAmountIn) {
        IERC20 usdc = manager.USDC();

        // Cannot swap from USDC, as this is our target asset.
        require(
            asset != address(usdc),
            GmxFrfStrategyErrors.SWAP_CALLBACK_LOGIC_CANNOT_SWAP_USDC
        );

        // Get the value of the tokens being swapped. This is important so we can evaluate the equivalent in terms of USDC.
        uint256 valueToken = Pricing.getTokenValueUSD(manager, asset, amount);

        // Get the value of the tokens being swapped in terms of USDC.
        // Accounts for cases where USDC depegs, possibly resulting in it being impossible to fill an order assuming the price is $1.
        uint256 valueInUsdc = Pricing.getTokenAmountForUSD(
            manager,
            address(usdc),
            valueToken
        );

        // Account for slippage to determine the minimum amount of USDC that should be recieved after the callback function's
        // execution is complete.
        uint256 minimumUSDCRecieved = valueInUsdc -
            valueInUsdc.percentToFraction(maxSlippagePercent);

        // Expected USDC must be greater than zero, otherwise this would allow stealing assets from the contract when rounding down.
        require(
            minimumUSDCRecieved > 0,
            GmxFrfStrategyErrors
                .SWAP_CALLBACK_LOGIC_NO_BALANCE_AFTER_SLIPPAGE_APPLIED
        );

        // Get the balance of USDC before the swap. This is used to determine the change in the balance of USDC to check if at least `expectedUSDC` was paid back.
        uint256 balanceUSDCBefore = usdc.balanceOf(address(this));

        // Transfer the tokens to the specified reciever.
        IERC20(asset).safeTransfer(tokenReceiever, amount);

        // Enter the callback, handing over execution the callback through the `SWAP_CALLBACK_RELAYER`.
        manager.SWAP_CALLBACK_RELAYER().relaySwapCallback(
            callback,
            amount,
            minimumUSDCRecieved,
            data
        );

        usdcAmountIn = usdc.balanceOf(address(this)) - balanceUSDCBefore;

        // Check to make sure the minimum amount of assets, which was calculated above using the `maxSlippagePercent`,
        // was returned to the contract.
        require(
            usdcAmountIn >= minimumUSDCRecieved,
            GmxFrfStrategyErrors.SWAP_CALLBACK_LOGIC_INSUFFICIENT_USDC_RETURNED
        );

        return usdcAmountIn;
    }
}

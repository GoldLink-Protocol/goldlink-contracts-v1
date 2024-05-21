// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { ISwapCallbackRelayer } from "./interfaces/ISwapCallbackRelayer.sol";
import { ISwapCallbackHandler } from "./interfaces/ISwapCallbackHandler.sol";

/**
 * @title SwapCallbackRelayer
 * @author GoldLink
 *
 * @notice Contract that serves as a middle man for execution callback functions. This contract
 * prevents collision risks with the `ISwapCallbackHandler.handleSwapCallback` function
 * potentially allowing for malicious calls from a strategy account using the account `msg.sender` context.
 */
contract SwapCallbackRelayer is ISwapCallbackRelayer {
    // ============ External Functions ============

    /**
     * @notice Relays a swap callback, executing on behalf of a caller to prevent collision risk.
     * @param callbackHandler   The address of the callback handler.
     * @param tokensToLiquidate The amount of tokens to liquidate during the callback.
     * @param expectedUsdc      The expected USDC received after the callback.
     */
    function relaySwapCallback(
        address callbackHandler,
        uint256 tokensToLiquidate,
        uint256 expectedUsdc
    ) external {
        ISwapCallbackHandler(callbackHandler).handleSwapCallback(
            tokensToLiquidate,
            expectedUsdc
        );
    }
}

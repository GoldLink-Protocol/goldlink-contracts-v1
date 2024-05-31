// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IUniswapV3SwapCallback } from "./external/IUniswapV3SwapCallback.sol";
import { IUniswapV3PoolActions } from "./external/IUniswapV3PoolActions.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SwapHandler
 * @author Trevor Judice
 *
 * @dev Contract that handles execution of different methods on the `GmxFrfStrategyAccount` that require callback functionality.
 * This contract should only contain funds during callback execution, as funds can be taken by anyone.
 */
contract SwapHandler is IUniswapV3SwapCallback {
    // ============ Enums ============
    enum SwapType {
        Liquidation,
        Rebalance,
        Assets
    }

    // ============ Structs ============

    struct SwapData {
        // The type of callback swap that is being done. Useful for determining if remainder should be sent as fee.
        SwapType swapType;
        // The address of the account being liquidated.
        address account;
        // The receiver of the fees, if any, associated with the swap.
        address feeReceiver;
        // UniswapV3 pool to swap tokens in. Must be paired against USDC.
        IUniswapV3PoolActions pool;
        // Token being sent to the pool. This should correspond to `token0` if `zeroForOne` is true, and `token1` if `zeroForOne` is false,
        // i.e. whatever asset in the pair is not USDC.
        IERC20 assetToSend;
        // Uniswap parameter for denoting the direction of the swap.
        bool zeroForOne;
        // Uniswap parameter for denoting the amount specified (either exact input or exact output).
        int256 amountSpecified;
        // Uniswap parameter for denoting the slippage tolerance based on the sqrtPriceLimit.
        uint160 sqrtPriceLimitX96;
    }

    // ============ Constants ============

    /// @dev USDC address.
    IERC20 immutable USDC;

    constructor(IERC20 usdc) {
        USDC = usdc;
    }

    /**
     * @notice Handles the callback function sent by the GmxFrfStrategyAccount (relayed via the SwapCallbackRelayer).
     * Cannot be called by an EOA, and can only be called if the original call tha triggered the callback function originated from this contract.
     */
    function handleSwapCallback(
        uint256 tokensToLiquidate,
        uint256 expectedUsdc,
        bytes memory data
    ) external {
        SwapData memory dat = abi.decode(data, (SwapData));

        dat.pool.swap(
            address(this),
            dat.zeroForOne,
            dat.amountSpecified,
            dat.sqrtPriceLimitX96,
            data
        );

        uint256 balance = USDC.balanceOf(address(this));

        uint256 sendAmount = (dat.swapType == SwapType.Assets)
            ? balance
            : expectedUsdc;

        USDC.transfer(dat.account, sendAmount);

        if (balance - sendAmount > 0) {
            USDC.transfer(dat.feeReceiver, balance - sendAmount);
        }

        uint256 assetBalance = dat.assetToSend.balanceOf(address(this));

        if (assetBalance > 0) {
            dat.assetToSend.transfer(dat.feeReceiver, assetBalance);
        }
    }

    /**
     * @notice Handles the callback function sent by the UniswapV3 pool that determines how many tokens should be sent to the pool.
     */
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        SwapData memory dat = abi.decode(data, (SwapData));
        if (amount0Delta > 0) {
            dat.assetToSend.transfer(msg.sender, uint256(amount0Delta));
            return;
        }
        dat.assetToSend.transfer(msg.sender, uint256(amount1Delta));
    }
}

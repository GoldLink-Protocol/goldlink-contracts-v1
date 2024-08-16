// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { MockAccountHelpers } from "./MockDeployment/MockAccountHelpers.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import {
    DeltaConvergenceMath
} from "@contracts/strategies/gmxFrf/libraries/DeltaConvergenceMath.sol";
import { Errors } from "@contracts/libraries/Errors.sol";

contract GmxFrfExecuteSwapAssetsTest is MockAccountHelpers {
    // Modifier Checks
    function testExecuteSwapAssetsNotOwner() public {
        vm.prank(address(1));
        _expectRevert(Errors.STRATEGY_ACCOUNT_SENDER_IS_NOT_OWNER);
        ACCOUNT.executeSwapAssets(
            ETH_USD_MARKET,
            1,
            address(this),
            address(this),
            new bytes(0)
        );
    }

    function testExecuteSwapAssetsLiquidationActive() public {
        _sendFromAccount(address(USDC), address(this), 40000000000);
        ACCOUNT.executeInitiateLiquidation();
        _expectRevert(
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_ACTIVE
        );
        ACCOUNT.executeSwapAssets(
            ETH_USD_MARKET,
            1,
            address(this),
            address(this),
            new bytes(0)
        );
    }

    function testExecuteSwapAssetsNoLoanActive() public {
        ACCOUNT.executeRepayLoan(40000000000);
        _expectRevert(Errors.STRATEGY_ACCOUNT_ACCOUNT_HAS_NO_LOAN);
        ACCOUNT.executeSwapAssets(
            ETH_USD_MARKET,
            1,
            address(this),
            address(this),
            new bytes(0)
        );
    }

    function testExecuteSwapAssetsMarketNotApproved() public {
        _expectRevert(
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
        ACCOUNT.executeSwapAssets(
            address(2),
            1,
            address(this),
            address(this),
            new bytes(0)
        );
    }

    function testExecuteSwapAssetsMoreThanAccountBalance() public {
        WETH.transfer(address(ACCOUNT), 1e18);
        _expectRevert(
            GmxFrfStrategyErrors
                .CANNOT_WITHDRAW_MORE_TOKENS_THAN_ACCOUNT_BALANCE
        );
        ACCOUNT.executeSwapAssets(
            ETH_USD_MARKET,
            2e18,
            address(this),
            address(this),
            new bytes(0)
        );
    }

    function testExecuteSwapAssetsNotEnoughReturned() public {
        WETH.transfer(address(ACCOUNT), 1e18);
        tmpCallbackDataHash = keccak256(abi.encode(CallbackCommands(1)));
        _expectRevert(
            GmxFrfStrategyErrors.SWAP_CALLBACK_LOGIC_INSUFFICIENT_USDC_RETURNED
        );
        ACCOUNT.executeSwapAssets(
            ETH_USD_MARKET,
            1e18,
            address(this),
            address(this),
            abi.encode(CallbackCommands(1))
        );
    }

    function testExecuteSwapAssetsPositionIsShort() public {
        _increase(1e9);
        WETH.transfer(address(ACCOUNT), 100);
        _expectRevert(
            GmxFrfStrategyErrors
                .CANNOT_WITHDRAW_FROM_MARKET_IF_ACCOUNT_MARKET_DELTA_IS_SHORT
        );
        ACCOUNT.executeSwapAssets(
            ETH_USD_MARKET,
            100,
            address(this),
            address(this),
            new bytes(0)
        );
    }

    function testExecuteSwapAssetsAmountIsGreaterThanDeltaDifference() public {
        _increase(1e9);
        DeltaConvergenceMath.PositionTokenBreakdown
            memory b = _getAccountPositionDelta(
                address(ACCOUNT),
                ETH_USD_MARKET
            );
        assert(b.tokensShort > b.tokensLong);
        uint256 diff = b.tokensShort - b.tokensLong;
        WETH.transfer(address(ACCOUNT), diff + 1);
        USDC.transfer(address(ACCOUNT), USDC.balanceOf(address(ACCOUNT))); // So buffer is okay.
        _expectRevert(
            GmxFrfStrategyErrors
                .REQUESTED_WITHDRAWAL_AMOUNT_EXCEEDS_CURRENT_DELTA_DIFFERENCE
        );
        ACCOUNT.executeSwapAssets(
            ETH_USD_MARKET,
            diff + 1,
            address(this),
            address(this),
            new bytes(0)
        );
    }

    function testSwapAssetsNoPositionWorksPartial() public {
        uint256 usdcToSend = 2000e6;
        uint256 wethToSend = 0.5e18;
        WETH.transfer(address(ACCOUNT), 1e18);
        (uint256 usdcBefore, uint256 wethBefore) = _getAccountBalances();
        bytes memory c = abi.encode(CallbackCommands(usdcToSend));
        tmpCallbackDataHash = keccak256(c);
        ACCOUNT.executeSwapAssets(
            ETH_USD_MARKET,
            wethToSend,
            address(this),
            address(this),
            c
        );
        (uint256 usdcAfter, uint256 wethAfter) = _getAccountBalances();
        console.log(wethBefore, wethAfter);
        console.log(usdcBefore, usdcAfter);
        assert(usdcBefore == usdcAfter - usdcToSend);
        assert(wethBefore == wethAfter + wethToSend);
    }

    function testSwapAssetsNoPositionWorksFull() public {
        uint256 usdcToSend = 4000e6;
        uint256 wethToSend = 1e18;
        WETH.transfer(address(ACCOUNT), 1e18);
        (uint256 usdcBefore, uint256 wethBefore) = _getAccountBalances();
        bytes memory c = abi.encode(CallbackCommands(usdcToSend));
        tmpCallbackDataHash = keccak256(c);
        ACCOUNT.executeSwapAssets(
            ETH_USD_MARKET,
            wethToSend,
            address(this),
            address(this),
            c
        );
        (uint256 usdcAfter, uint256 wethAfter) = _getAccountBalances();
        console.log(wethBefore, wethAfter);
        console.log(usdcBefore, usdcAfter);
        assert(usdcBefore == usdcAfter - usdcToSend);
        assert(wethBefore == wethAfter + wethToSend);
    }

    function testExecuteSwapAssetsMarketZeroAmount() public {
        uint256 usdcBefore = USDC.balanceOf(address(ACCOUNT));
        ACCOUNT.executeSwapAssets(
            ETH_USD_MARKET,
            0,
            address(this),
            address(this),
            new bytes(0)
        );
        assert(usdcBefore == USDC.balanceOf(address(ACCOUNT)));
    }

    receive() external payable {}

    bytes32 tmpCallbackDataHash;

    struct CallbackCommands {
        uint256 usdcAmountToSend;
    }

    /// @dev Handle a swap callback.
    function handleSwapCallback(
        uint256 /* tokensToLiquidate */,
        uint256 expectedUsdc,
        bytes memory data
    ) external {
        assert(tmpCallbackDataHash == keccak256(data));

        CallbackCommands memory cmd = abi.decode(data, (CallbackCommands));
        if (cmd.usdcAmountToSend == 0) {
            USDC.transfer(address(ACCOUNT), expectedUsdc);
            return;
        }

        USDC.transfer(address(ACCOUNT), cmd.usdcAmountToSend);
    }
}

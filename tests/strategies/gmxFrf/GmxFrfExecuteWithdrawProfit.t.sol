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
import {
    WithdrawalLogic
} from "@contracts/strategies/gmxFrf/libraries/WithdrawalLogic.sol";
import { Errors } from "@contracts/libraries/Errors.sol";

contract GmxFrfExecuteWithdrawProfitTest is MockAccountHelpers {
    function testGmxFrfExecuteWithdrawProfitNotOwner() public {
        vm.prank(address(10));
        _expectRevert(Errors.STRATEGY_ACCOUNT_SENDER_IS_NOT_OWNER);
        ACCOUNT.executeWithdrawProfit(_params(1));
    }

    function testGmxFrfExecuteWithdrawProfitLiquidationActive() public {
        _sendFromAccount(address(USDC), address(this), 40000000000);
        ACCOUNT.executeInitiateLiquidation();
        _expectRevert(
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_ACTIVE
        );
        ACCOUNT.executeWithdrawProfit(_params(1));
    }

    function testGmxFrfExecuteWithdrawProfitNoLoanActive() public {
        ACCOUNT.executeRepayLoan(USDC.balanceOf(address(ACCOUNT)));
        _expectRevert(Errors.STRATEGY_ACCOUNT_ACCOUNT_HAS_NO_LOAN);
        ACCOUNT.executeWithdrawProfit(_params(1));
    }

    function testGmxFrfExecuteWithdrawProfitMarketNotApproved() public {
        _expectRevert(
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
        ACCOUNT.executeWithdrawProfit(_params(address(1), 1));
    }

    function testGmxFrfExecuteWithdrawProfitAmountGreaterThanBalance() public {
        _expectRevert(
            GmxFrfStrategyErrors
                .CANNOT_WITHDRAW_MORE_TOKENS_THAN_ACCOUNT_BALANCE
        );
        ACCOUNT.executeWithdrawProfit(_params(1));
    }

    function testGmxFrfExecuteWithdrawProfitDeltaIsNegative() public {
        _increase(1e9);
        WETH.transfer(address(ACCOUNT), 1);
        _expectRevert(
            GmxFrfStrategyErrors
                .CANNOT_WITHDRAW_FROM_MARKET_IF_ACCOUNT_MARKET_DELTA_IS_SHORT
        );
        ACCOUNT.executeWithdrawProfit(_params(1));
    }

    function testGmxFrfExecuteWithdrawProfitMoreThanDeltaDifference() public {
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
        ACCOUNT.executeWithdrawProfit(_params(diff + 1));
    }

    function testGmxFrfExecuteWithdrawProfitWithdrawalRemainingValueLessThanBuffer()
        public
    {
        WETH.transfer(address(ACCOUNT), 1e17);
        _expectRevert(
            GmxFrfStrategyErrors
                .CANNOT_WITHDRAW_BELOW_THE_ACCOUNTS_LOAN_VALUE_WITH_BUFFER_APPLIED
        );
        ACCOUNT.executeWithdrawProfit(_params(1e16));
    }

    function testGmxFrfExecuteWithdrawProfitHealthScoreBelowOpen() public {
        ARB.transfer(address(ACCOUNT), 10000e18);
        WETH.transfer(address(ACCOUNT), 1e18);
        vm.warp(block.timestamp + 1000 days); // accrue interest.
        ETH_USD_ORACLE_MOCK.poke();
        USDC_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        GMX_USD_ORACLE_MOCK.poke();
        _expectRevert(
            GmxFrfStrategyErrors
                .WITHDRAWAL_BRINGS_ACCOUNT_BELOW_MINIMUM_OPEN_HEALTH_SCORE
        );
        ACCOUNT.executeWithdrawProfit(_params(1));
    }

    function testGmxFrfExecuteWithdrawProfitBasic() public {
        WETH.transfer(address(ACCOUNT), 1e19);
        (uint256 usdcBefore, uint256 wethBefore) = _getAccountBalances();
        uint256 recieveWethBefore = WETH.balanceOf(address(this));
        ACCOUNT.executeWithdrawProfit(_params(5e18));
        (uint256 usdcAfter, uint256 wethAfter) = _getAccountBalances();
        assert(usdcBefore == usdcAfter);
        assert(wethBefore - 5e18 == wethAfter);
        assert(recieveWethBefore + 5e18 == WETH.balanceOf(address(this)));
    }

    function testGmxFrfExecuteWithdrawProfitZeroAmount() public {
        WETH.transfer(address(ACCOUNT), 1e19);
        (uint256 usdcBefore, uint256 wethBefore) = _getAccountBalances();
        ACCOUNT.executeWithdrawProfit(_params(0));
        (uint256 usdcAfter, uint256 wethAfter) = _getAccountBalances();
        assert(usdcBefore == usdcAfter);
        assert(wethBefore == wethAfter);
    }

    receive() external payable {}

    function _params(
        uint256 amount
    ) internal view returns (WithdrawalLogic.WithdrawProfitParams memory) {
        return
            WithdrawalLogic.WithdrawProfitParams(
                ETH_USD_MARKET,
                amount,
                address(this)
            );
    }

    function _params(
        address market,
        uint256 amount
    ) internal view returns (WithdrawalLogic.WithdrawProfitParams memory) {
        return
            WithdrawalLogic.WithdrawProfitParams(market, amount, address(this));
    }
}

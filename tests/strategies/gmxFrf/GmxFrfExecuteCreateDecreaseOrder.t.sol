// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {
    GmxFrfStrategyAccount
} from "@contracts/strategies/gmxFrf/GmxFrfStrategyAccount.sol";
import { MockAccountHelpers } from "./MockDeployment/MockAccountHelpers.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import { Errors } from "@contracts/libraries/Errors.sol";

contract GmxFrfExecuteCreateDecreaseOrderTest is MockAccountHelpers {
    // ============ ExecuteCreateIncreaseOrder ============

    // Modifier Checks
    function testExecuteCreateDecreaseOrderNotOwner() public {
        payable(address(10)).transfer(0.01 ether);
        vm.prank(address(10));
        _expectRevert(Errors.STRATEGY_ACCOUNT_SENDER_IS_NOT_OWNER);
        ACCOUNT.executeCreateDecreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e33,
            0.01 ether
        );
    }

    function testExecuteCreateDecreaseOrderLiquidationActive() public {
        _sendFromAccount(address(USDC), address(this), 40000000000);
        ACCOUNT.executeInitiateLiquidation();
        _expectRevert(
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_ACTIVE
        );
        ACCOUNT.executeCreateDecreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e33,
            0.01 ether
        );
    }

    function testExecuteCreateDecreaseOrderLoanNotActive() public {
        address newAccount = BANK.executeOpenAccount(address(this));
        _expectRevert(Errors.STRATEGY_ACCOUNT_ACCOUNT_HAS_NO_LOAN);
        GmxFrfStrategyAccount(payable(newAccount)).executeCreateIncreaseOrder{
            value: 0.01 ether
        }(ETH_USD_MARKET, 1e8, 0.01 ether);
    }

    function testExecuteCreateDecreaseOrderMarketNotApproved() public {
        _expectRevert(
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            address(1),
            1e8,
            0.01 ether
        );
    }

    function testExecuteIncreaseOrderCannotPayFee() public {
        _expectRevert(
            GmxFrfStrategyErrors.MSG_VALUE_LESS_THAN_PROVIDED_EXECUTION_FEE
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.00000001 ether }(
            ETH_USD_MARKET,
            1e8,
            0.01 ether
        );
    }

    function testExecuteCreateDecreaseOrderHasPendingOrders() public {
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e8,
            0.01 ether
        );
        _decreaseExpecting(
            1e32,
            GmxFrfStrategyErrors.ORDER_VALIDATION_MARKET_HAS_PENDING_ORDERS
        );
    }

    function testExecuteCreateDecreaseOrderOrderSizeTooSmall() public {
        _increase(1e8);
        _decreaseExpecting(
            1,
            GmxFrfStrategyErrors.ORDER_VALIDATION_ORDER_SIZE_IS_TOO_SMALL
        );
    }

    function testExecuteDecreaseOrderPositionSizeTooSmall() public {
        _increase(1e8);
        uint256 sizeDelta = _getAccountPosition().position.numbers.sizeInUsd;
        _decreaseExpecting(
            sizeDelta - 1,
            GmxFrfStrategyErrors.ORDER_VALIDATION_POSITION_SIZE_IS_TOO_SMALL
        );
    }

    function testExecuteCreateDecreaseOrderInvalidExecutionFeeProvided()
        public
    {
        _increase(1e10);
        _expectRevert(
            GmxFrfStrategyErrors
                .ORDER_VALIDATION_PROVIDED_EXECUTION_FEE_IS_TOO_LOW
        );
        ACCOUNT.executeCreateDecreaseOrder{ value: 0.00000001 ether }(
            ETH_USD_MARKET,
            1e32,
            0.00000001 ether
        );
    }

    function testExecuteCreateDecreaseOrderPositionIsBalancedSmall() public {
        _increase(1e10);
        _decrease(_size() / 20);
    }

    function testExecuteCreateDecreaseOrderPositionIsBalancedMedium() public {
        _increase(1e10);
        _decrease(_size() / 3);
    }

    function testExecuteCreateDecreaseOrderPositionIsBalancedLarge() public {
        _increase(1e10);
        _decrease((_size() * 2) / 3);
    }

    function testExecuteCreateDecreaseOrderPositionIsBalancedFull() public {
        _increase(1e10);
        _decrease(_size());
        assert(_size() == 0);
    }

    function testExecuteCreateDecreaseOrderPositionPnlPositiveSmall() public {
        _increase(1e10);
        ETH_USD_ORACLE_MOCK.updateAnswer(2000e8);
        USDC_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        _decrease(_size() / 20);
    }

    function testExecuteCreateDecreaseOrderPositionPnlPositiveMedium() public {
        _increase(1e10);
        ETH_USD_ORACLE_MOCK.updateAnswer(2000e8);
        USDC_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        _decrease(_size() / 4);
    }

    function testExecuteCreateDecreaseOrderPositionPnlPositiveLarge() public {
        _increase(1e10);
        ETH_USD_ORACLE_MOCK.updateAnswer(2000e8);
        USDC_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        _decrease((_size() * 2) / 3);
    }

    function testExecuteCreateDecreaseOrderPositionPnlPositiveFull() public {
        _increase(1e10);
        ETH_USD_ORACLE_MOCK.updateAnswer(2000e8);
        USDC_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        _decrease(_size());
    }

    function testExecuteCreateDecreaseOrderPositionPnlNegativeSmall() public {
        _increase(1e10);
        ETH_USD_ORACLE_MOCK.updateAnswer(8000e8);
        USDC_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        _decrease(_size() / 20);
    }

    function testExecuteCreateDecreaseOrderPositionPnlNegativeMedium() public {
        _increase(1e10);
        ETH_USD_ORACLE_MOCK.updateAnswer(8000e8);
        USDC_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        _decrease(_size() / 4);
    }

    function testExecuteCreateDecreaseOrderPositionPnlNegativeLarge() public {
        _increase(1e10);
        ETH_USD_ORACLE_MOCK.updateAnswer(8000e8);
        USDC_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        _decrease((_size() * 2) / 3);
    }

    function testExecuteCreateDecreaseOrderPositionPnlNegativeFull() public {
        _increase(1e10);
        ETH_USD_ORACLE_MOCK.updateAnswer(8000e8);
        USDC_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        _decrease(_size());
    }

    receive() external payable {}
}

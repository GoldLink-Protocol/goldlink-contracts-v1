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

contract GmxFrfExecuteCancelOrderTest is MockAccountHelpers {
    // ============ ExecuteCancelOrder ============

    // Modifier Checks
    function testExecuteCancelOrderNotOwner() public {
        vm.prank(address(10));
        bytes32 b;
        _expectRevert(Errors.STRATEGY_ACCOUNT_SENDER_IS_NOT_OWNER);
        ACCOUNT.executeCancelOrder(b);
    }

    function testExecuteCancelOrderLiquidationActive() public {
        _sendFromAccount(address(USDC), address(this), 40000000000);
        ACCOUNT.executeInitiateLiquidation();
        bytes32 b;
        _expectRevert(
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_ACTIVE
        );
        ACCOUNT.executeCancelOrder(b);
    }

    function testExecuteCancelOrderLoanNotActive() public {
        address newAccount = BANK.executeOpenAccount(address(this));
        _expectRevert(Errors.STRATEGY_ACCOUNT_ACCOUNT_HAS_NO_LOAN);
        GmxFrfStrategyAccount(payable(newAccount)).executeCreateIncreaseOrder{
            value: 0.01 ether
        }(ETH_USD_MARKET, 1e8, 0.01 ether);
    }

    function testExecuteCancelOrderMarketNotApproved() public {
        _expectRevert(
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            address(1),
            1e8,
            0.01 ether
        );
    }

    function testExecuteCancelOrderWorks() public {
        (, bytes32 orderKey) = ACCOUNT.executeCreateIncreaseOrder{
            value: 1 ether
        }(ETH_USD_MARKET, 1e8, 1 ether);
        vm.roll(block.number + 200);
        vm.warp(block.timestamp + 1000);
        ACCOUNT.executeCancelOrder(orderKey);
    }

    receive() external payable {}
}

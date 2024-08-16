// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { MockAccountHelpers } from "./MockDeployment/MockAccountHelpers.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import { Errors } from "@contracts/libraries/Errors.sol";

contract GmxFrfExecuteReleveragePositionTest is MockAccountHelpers {
    // Modifier Checks
    function testExecuteReleveragePositionLiquidationActive() public {
        _initiateLiquidation();
        _expectRevert(
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_ACTIVE
        );
        ACCOUNT.executeReleveragePosition{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e5,
            0.01 ether
        );
    }

    function testExecuteReleveragePositionCannotPayFee() public {
        _expectRevert(
            GmxFrfStrategyErrors.MSG_VALUE_LESS_THAN_PROVIDED_EXECUTION_FEE
        );
        ACCOUNT.executeReleveragePosition{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e5,
            0.02 ether
        );
    }

    function testExecuteReleveragePositionMarketNotApproved() public {
        _expectRevert(
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
        ACCOUNT.executeReleveragePosition{ value: 0.01 ether }(
            address(1),
            1e5,
            0.01 ether
        );
    }

    function testExecuteReleveragePositionHasActiveOrderCantCancel() public {
        _increase(1000e6);
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1000e6,
            0.01 ether
        );
        uint256 size = _size();
        vm.expectRevert();
        ACCOUNT.executeReleveragePosition{ value: 0.01 ether }(
            ETH_USD_MARKET,
            size,
            0.01 ether
        );
    }

    function testExecuteReleveragePositionLeverageIsBelowThreshold() public {
        _increase(1000e6);
        uint256 size = _size();
        _expectRevert(
            GmxFrfStrategyErrors
                .LIQUIDATION_MANAGEMENT_POSITION_IS_WITHIN_MAX_LEVERAGE
        );
        ACCOUNT.executeReleveragePosition{ value: 0.01 ether }(
            ETH_USD_MARKET,
            size,
            0.01 ether
        );
    }

    receive() external payable {}
}

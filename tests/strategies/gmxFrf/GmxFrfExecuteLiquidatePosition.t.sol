// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { MockAccountHelpers } from "./MockDeployment/MockAccountHelpers.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import { Errors } from "@contracts/libraries/Errors.sol";
import { PercentMath } from "@contracts/libraries/PercentMath.sol";

contract GmxFrfExecuteLiquidatePositionTest is MockAccountHelpers {
    using PercentMath for uint256;

    // Modifier Checks
    function testExecuteLiquidatePositionLiquidationInactive() public {
        _expectRevert(
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_INACTIVE
        );
        ACCOUNT.executeLiquidatePosition{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e5,
            0.01 ether
        );
    }

    function testExecuteLiquidatePositionCannotPayFee() public {
        _initiateLiquidation();
        _expectRevert(
            GmxFrfStrategyErrors.MSG_VALUE_LESS_THAN_PROVIDED_EXECUTION_FEE
        );
        ACCOUNT.executeLiquidatePosition{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e5,
            0.02 ether
        );
    }

    function testExecuteLiquidatePositionMarketNotApproved() public {
        _initiateLiquidation();
        _expectRevert(
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
        ACCOUNT.executeLiquidatePosition{ value: 0.01 ether }(
            address(1),
            1e5,
            0.01 ether
        );
    }

    function testExecuteLiquidatePositionHasActiveOrderCantCancel() public {
        _increase(1000e6);
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1000e6,
            0.01 ether
        );
        _initiateLiquidation();
        uint256 size = _size();
        vm.expectRevert();
        ACCOUNT.executeLiquidatePosition{ value: 0.01 ether }(
            ETH_USD_MARKET,
            size,
            0.01 ether
        );
    }

    function testExecuteLiquidatePositionHasActiveOrderCantCancelUserOrder()
        public
    {
        _increase(1000e6);
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1000e6,
            0.01 ether
        );
        _initiateLiquidation();
        uint256 size = _size();
        vm.expectRevert();
        ACCOUNT.executeLiquidatePosition{ value: 0.01 ether }(
            ETH_USD_MARKET,
            size,
            0.01 ether
        );
    }

    function testExecuteLiquidatePositionHasActiveOrderCanCancel() public {
        _increase(1000e6);
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1000e6,
            0.01 ether
        );
        _initiateLiquidation();
        uint256 size = _size();
        vm.roll(block.number + 200);
        vm.warp(block.timestamp + 1000);
        ACCOUNT.executeLiquidatePosition{ value: 0.01 ether }(
            ETH_USD_MARKET,
            size,
            0.01 ether
        );
    }

    function testExecuteLiquidatePositionPartial() public {
        _increase(1000e6);
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1000e6,
            0.01 ether
        );
        _initiateLiquidation();
        uint256 size = _size() / 2;
        vm.roll(block.number + 200);
        vm.warp(block.timestamp + 1000);
        uint256 accountBalanceBefore = USDC.balanceOf(address(ACCOUNT));
        uint256 liquidatorBalanceBefore = USDC.balanceOf(address(this));
        (, bytes32 orderKey) = ACCOUNT.executeLiquidatePosition{
            value: 0.01 ether
        }(ETH_USD_MARKET, size, 0.01 ether);
        _executeGmxOrder(orderKey);
        uint256 accountBalanceAfter = USDC.balanceOf(address(ACCOUNT));
        uint256 liquidatorBalanceAfter = USDC.balanceOf(address(this));
        uint256 output = (accountBalanceAfter - accountBalanceBefore) +
            (liquidatorBalanceAfter - liquidatorBalanceBefore);
        uint256 feePct = (liquidatorBalanceAfter - liquidatorBalanceBefore)
            .fractionToPercent(output);
        assert(
            feePct <=
                MANAGER
                    .getMarketConfiguration(ETH_USD_MARKET)
                    .unwindParameters
                    .unwindFee
        );
    }

    function testExecuteLiquidatePositionFull() public {
        _increase(1000e6);
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1000e6,
            0.01 ether
        );
        _initiateLiquidation();
        uint256 size = _size();
        vm.roll(block.number + 200);
        vm.warp(block.timestamp + 1000);
        uint256 accountBalanceBefore = USDC.balanceOf(address(ACCOUNT));
        uint256 liquidatorBalanceBefore = USDC.balanceOf(address(this));
        (, bytes32 orderKey) = ACCOUNT.executeLiquidatePosition{
            value: 0.01 ether
        }(ETH_USD_MARKET, size, 0.01 ether);
        _executeGmxOrder(orderKey);
        uint256 accountBalanceAfter = USDC.balanceOf(address(ACCOUNT));
        uint256 liquidatorBalanceAfter = USDC.balanceOf(address(this));
        uint256 output = (accountBalanceAfter - accountBalanceBefore) +
            (liquidatorBalanceAfter - liquidatorBalanceBefore);
        uint256 feePct = (liquidatorBalanceAfter - liquidatorBalanceBefore)
            .fractionToPercent(output);
        assert(
            feePct <=
                MANAGER
                    .getMarketConfiguration(ETH_USD_MARKET)
                    .unwindParameters
                    .unwindFee
        );
    }

    receive() external payable {}
}

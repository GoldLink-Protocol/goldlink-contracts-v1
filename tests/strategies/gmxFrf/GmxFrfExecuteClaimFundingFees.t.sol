// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { MockAccountHelpers } from "./MockDeployment/MockAccountHelpers.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import { Errors } from "@contracts/libraries/Errors.sol";

contract GmxFrfExecuteClaimFundingFeesTest is MockAccountHelpers {
    // ============ ExecuteClaimFundingFees ============

    function testExecuteClaimFundingFees() public {
        _increase(1e8);
        vm.warp(block.timestamp + 8640000);
        ETH_USD_ORACLE_MOCK.poke();
        USDC_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        _decrease(_size());
        address[] memory markets = new address[](2);
        address[] memory assets = new address[](2);
        markets[0] = ETH_USD_MARKET;
        markets[1] = ETH_USD_MARKET;
        assets[0] = address(USDC);
        assets[1] = address(WETH);
        uint256 usdcBefore = USDC.balanceOf(address(ACCOUNT));
        uint256 wethBefore = WETH.balanceOf(address(ACCOUNT));
        ACCOUNT.executeClaimFundingFees(markets, assets);
        require(usdcBefore < USDC.balanceOf(address(ACCOUNT)));
        require(wethBefore < WETH.balanceOf(address(ACCOUNT)));
    }

    receive() external payable {}
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import { MockAccountHelpers } from "./MockAccountHelpers.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GmxFrfStrategyMetadata } from "../GmxFrfStrategyMetadata.sol";
import { SwapHandler } from "./liquidator/SwapHandler.sol";

// 0xa11b501c2dd83acd29f6727570f2502faaa617f2
contract MockAccountTests is MockAccountHelpers {
    address ethMarket = GmxFrfStrategyMetadata.GMX_V2_ETH_USDC;

    // ==================== Liqudation Tests ====================

    function testInitiateLiquidationCannotLiquidate() public {
        vm.expectRevert();
        ACCOUNT.executeInitiateLiquidation();
    }

    // Covers critical case cited in audit.
    function testInitiateLiquidationCannotLiquidateActiveOrder() public {
        _sendIncreaseOrder(_createIncreaseOrder(ethMarket, 1e33, 1.8e9));
        vm.expectRevert();
        ACCOUNT.executeInitiateLiquidation();
    }

    function testLiquidateAssets() public {
        _sendFromAccount(address(USDC), address(this), 1.5e9);
        _fundAccount(address(WETH), 3e16);
        ACCOUNT.executeInitiateLiquidation();

        uint256 accountUsdcBefore = USDC.balanceOf(address(ACCOUNT));
        uint256 wethBalanceBefore = WETH.balanceOf(address(ACCOUNT));
        console.log(wethBalanceBefore);

        uint256 recieverUsdcBalanceBefore = USDC.balanceOf(address(this));
        uint256 recieverWethBalanceBefore = WETH.balanceOf(address(this));
        SwapHandler.SwapData memory dat = SwapHandler.SwapData(
            SwapHandler.SwapType.Liquidation,
            address(ACCOUNT),
            address(this),
            WETH_USDC_UNIV3,
            IERC20(WETH),
            true,
            3e16,
            484016920170066100000
        );
        ACCOUNT.executeLiquidateAssets(
            address(WETH),
            3e16,
            address(SWAPHANDLER),
            address(SWAPHANDLER),
            abi.encode(dat)
        );

        assert(accountUsdcBefore < USDC.balanceOf(address(ACCOUNT)));
        assert(WETH.balanceOf(address(ACCOUNT)) == 0);
        assert(recieverUsdcBalanceBefore < USDC.balanceOf(address(this)));
        assert(USDC.balanceOf(address(SWAPHANDLER)) == 0);
        assert(WETH.balanceOf(address(SWAPHANDLER)) == 0);
    }
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { MockAccountHelpers } from "./MockDeployment/MockAccountHelpers.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import { Errors } from "@contracts/libraries/Errors.sol";

contract GmxFrfExecuteLiquidateAssetsTest is MockAccountHelpers {
    // Modifier Checks
    function testExecuteLiquidateAssetsNotInLiquidation() public {
        _expectRevert(
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_INACTIVE
        );
        ACCOUNT.executeLiquidateAssets(
            ETH_USD_MARKET,
            1,
            address(this),
            address(this),
            new bytes(0)
        );
    }

    function testExecuteLiquidateAssetsNotEnoughReturned() public {
        _initiateLiquidation();
        WETH.transfer(address(ACCOUNT), 1e18);
        bytes memory c = abi.encode(CallbackCommands(1));
        tmpCallbackDataHash = keccak256(c);
        _expectRevert(
            GmxFrfStrategyErrors.SWAP_CALLBACK_LOGIC_INSUFFICIENT_USDC_RETURNED
        );
        ACCOUNT.executeLiquidateAssets(
            address(WETH),
            1e18,
            address(this),
            address(this),
            c
        );
    }

    function testExecuteLiquidateAssetsTooMuchReturnedOK() public {
        _initiateLiquidation();
        WETH.transfer(address(ACCOUNT), 1e18);
        bytes memory c = abi.encode(CallbackCommands(10000e6));
        tmpCallbackDataHash = keccak256(c);
        ACCOUNT.executeLiquidateAssets(
            address(WETH),
            1e18,
            address(this),
            address(this),
            c
        );
    }

    function testExecuteLiquidateAssetsPartialOK() public {
        _initiateLiquidation();
        WETH.transfer(address(ACCOUNT), 1e18);
        bytes memory c = abi.encode(CallbackCommands(0));
        tmpCallbackDataHash = keccak256(c);
        ACCOUNT.executeLiquidateAssets(
            address(WETH),
            0.5e18,
            address(this),
            address(this),
            c
        );
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

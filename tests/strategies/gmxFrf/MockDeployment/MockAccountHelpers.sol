// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGmxV2OrderTypes} from "../../../../contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import { MockAccountGmxHelpers } from "./MockAccountGmxHelpers.sol";

abstract contract MockAccountHelpers is MockAccountGmxHelpers {

    function _fundAccount(address asset, uint256 amount) internal {
        IERC20(asset).transfer(address(ACCOUNT), amount);
    }

    function _sendFromAccount(address asset, address to, uint256 amount) internal {
        ACCOUNT.exec(asset, abi.encodeWithSignature("transfer(address,uint256)", to, amount));
    }

    function _sendIncreaseOrder(IGmxV2OrderTypes.CreateOrderParams memory order) internal returns (bytes32) {
        WETH.deposit{ value: 1e15 }();
        WETH.transfer(address(MANAGER.gmxV2OrderVault()), 1e15);
        _sendFromAccount(address(USDC), address(MANAGER.gmxV2OrderVault()), order.numbers.initialCollateralDeltaAmount);
        return _sendOrder(order);
    }

}

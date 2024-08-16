// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IGmxV2OrderTypes
} from "../../../../contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import { MockAccountGmxHelpers } from "./MockAccountGmxHelpers.sol";
import {
    DeltaConvergenceMath
} from "../../../../contracts/strategies/gmxFrf/libraries/DeltaConvergenceMath.sol";
import { MockAccountExtension } from "./MockAccountExtension.sol";

abstract contract MockAccountHelpers is MockAccountGmxHelpers {
    function _fundAccount(address asset, uint256 amount) internal {
        IERC20(asset).transfer(address(ACCOUNT), amount);
    }

    function _sendFromAccount(
        address asset,
        address to,
        uint256 amount
    ) internal {
        ACCOUNT.exec(
            asset,
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
    }

    function _sendIncreaseOrder(
        IGmxV2OrderTypes.CreateOrderParams memory order
    ) internal returns (bytes32) {
        WETH.deposit{ value: 1e15 }();
        WETH.transfer(address(MANAGER.gmxV2OrderVault()), 1e15);
        _sendFromAccount(
            address(USDC),
            address(MANAGER.gmxV2OrderVault()),
            order.numbers.initialCollateralDeltaAmount
        );
        return _sendOrder(order);
    }

    function _logAccountBreakdown(
        address account,
        address market
    ) internal view {
        DeltaConvergenceMath.PositionTokenBreakdown
            memory breakdown = _getAccountPositionDelta(account, market);

        console.log("================== Position Info ==================");
        console.log(
            "Position Size USD:",
            breakdown.positionInfo.position.numbers.sizeInUsd
        );
        console.log(
            "Position Size Tokens:",
            breakdown.positionInfo.position.numbers.sizeInTokens
        );
        console.log(
            "Collateral",
            breakdown.positionInfo.position.numbers.collateralAmount
        );
        console.log("Leverage:", breakdown.leverage);
        (uint256 prop, bool isShort) = DeltaConvergenceMath.getDeltaProportion(
            breakdown.tokensLong,
            breakdown.tokensShort
        );
        if (isShort) {
            console.log("Delta Proportion: -", prop);
        } else {
            console.log("Delta Proportion:", prop);
        }

        console.log("================== Funding Earned ==================");
        console.log("Long Token Unsettled:", breakdown.unsettledLongTokens);
        console.log("Long Token Claimable:", breakdown.claimableLongTokens);
        console.log(
            "Total Fees Owned: ",
            breakdown.fundingAndBorrowFeesLongTokens
        );
        console.log("Account Balance", breakdown.accountBalanceLongTokens);

        console.log("===============================================");
    }

    function _getAccountPositionDelta(
        address account,
        address market
    )
        internal
        view
        returns (DeltaConvergenceMath.PositionTokenBreakdown memory breakdown)
    {
        return
            DeltaConvergenceMath.getAccountMarketDelta(
                MANAGER,
                account,
                market,
                0,
                true
            );
    }

    function _createNewAccount(
        address owner
    ) internal returns (MockAccountExtension newAccount) {
        return MockAccountExtension(payable(BANK.executeOpenAccount(owner)));
    }

    function _toHex16(bytes16 data) private pure returns (bytes32 result) {
        result =
            (bytes32(data) &
                0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000) |
            ((bytes32(data) &
                0x0000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000000000) >>
                64);
        result =
            (result &
                0xFFFFFFFF000000000000000000000000FFFFFFFF000000000000000000000000) |
            ((result &
                0x00000000FFFFFFFF000000000000000000000000FFFFFFFF0000000000000000) >>
                32);
        result =
            (result &
                0xFFFF000000000000FFFF000000000000FFFF000000000000FFFF000000000000) |
            ((result &
                0x0000FFFF000000000000FFFF000000000000FFFF000000000000FFFF00000000) >>
                16);
        result =
            (result &
                0xFF000000FF000000FF000000FF000000FF000000FF000000FF000000FF000000) |
            ((result &
                0x00FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF0000) >>
                8);
        result =
            ((result &
                0xF000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000) >>
                4) |
            ((result &
                0x0F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F00) >>
                8);
        result = bytes32(
            0x3030303030303030303030303030303030303030303030303030303030303030 +
                uint256(result) +
                (((uint256(result) +
                    0x0606060606060606060606060606060606060606060606060606060606060606) >>
                    4) &
                    0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F) *
                7
        );
    }

    function _toHex(bytes32 data) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "0x",
                    _toHex16(bytes16(data)),
                    _toHex16(bytes16(data << 128))
                )
            );
    }

    function _initiateLiquidation() internal {
        _sendFromAccount(address(USDC), address(this), 20000000000);
        ACCOUNT.executeInitiateLiquidation();
    }
}

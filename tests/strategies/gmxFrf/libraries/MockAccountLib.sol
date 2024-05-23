// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;


import { IGmxV2OrderTypes } from "../../../../contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import { IWrappedNativeToken } from "../../../../contracts/adapters/shared/interfaces/IWrappedNativeToken.sol";
import {
    IGmxFrfStrategyManager
} from "../../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";


import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";



library MockAccountLib {
     function sendOrder(
        IGmxFrfStrategyManager manager,
        IGmxV2OrderTypes.CreateOrderParams memory order,
        uint256 executionFee
    ) external returns (bytes32 orderKey) {
        uint256 collateralToSend = 0;

        if (order.orderType != IGmxV2OrderTypes.OrderType.MarketDecrease) {
            collateralToSend = order.numbers.initialCollateralDeltaAmount;
        }

        // Transfer the collateral (if applicable) + the execution fee.
        transferOrderAssets(
            IERC20(order.addresses.initialCollateralToken),
            manager.WRAPPED_NATIVE_TOKEN(),
            collateralToSend,
            executionFee,
            manager.gmxV2OrderVault()
        );

        orderKey = manager.gmxV2ExchangeRouter().createOrder(order);

        return orderKey;
    }

    function transferOrderAssets(
        IERC20 initialCollateralToken,
        IWrappedNativeToken wrappedNativeToken,
        uint256 collateralTokenAmount,
        uint256 executionFee,
        address gmxV2OrderVault
    ) public {
        // Send wrapped native to GMX order vault. This amount can be just the gas stipend, or the
        // gas stipend + the amount of collateral we want to send to the GMX order vault.
        if (executionFee != 0) {
            // Wrap the native token.
            wrappedNativeToken.deposit{ value: executionFee }();
            // Transfer the wrapped native token to the GMX order vault.
            wrappedNativeToken.transfer(gmxV2OrderVault, executionFee);
        }

        // Don't need to do anything if it is zero.
        if (collateralTokenAmount != 0) {
            // Transfer the collateral token to the GMX order vault.
            initialCollateralToken.transfer(
                gmxV2OrderVault,
                collateralTokenAmount
            );
        }

        // It is important to note that, after this function is called, a method that triggers the `recordTransferIn` method on the
        // GmxV2ExchangeRouter MUST be called, otherwise funds will be lost. GMX accounts the assets in the exchange router assuming they were zero at the beggining of
        // the transaction, so if a method that calls `recordTransferIn` is not called after assets are transferred, GMX will not revert and there is no way
        // to recover these assets.
    }
}

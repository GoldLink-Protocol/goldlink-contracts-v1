// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IStrategyAccount } from "../../../interfaces/IStrategyAccount.sol";
import {
    IGmxV2OrderTypes
} from "../../../lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import {
    IGmxV2PositionTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";
import { WithdrawalLogic } from "../libraries/WithdrawalLogic.sol";

/**
 * @title IGmxFrfStrategyAccount
 * @author GoldLink
 *
 * @dev Interface for interacting with a Gmx Funding rate farming strategy account.
 */
interface IGmxFrfStrategyAccount is IStrategyAccount {
    // ============ Events ============

    /// @notice Emitted when creating an increase order.
    /// @param market   The market the order was created in.
    /// @param order    The order that was created via GMX.
    /// @param orderKey The key identifying the order.
    event CreateIncreaseOrder(
        address indexed market,
        IGmxV2OrderTypes.CreateOrderParams order,
        bytes32 orderKey
    );

    /// @notice Emitted when creating a decrease order.
    /// @param market   The market the order was created in.
    /// @param order    The order that was created via GMX.
    /// @param orderKey The key identifying the order.
    event CreateDecreaseOrder(
        address indexed market,
        IGmxV2OrderTypes.CreateOrderParams order,
        bytes32 orderKey
    );

    /// @notice Emitted when canceling an order.
    /// @param orderKey The key identifying the order.
    event CancelOrder(bytes32 orderKey);

    /// @notice Emitted when claiming funding fees.
    /// @param markets The markets funding fees were claimed for.
    /// @param assets  The assets the funding fees were claimed for.
    /// @param assets  The amounts claimed for each (market, asset) pairing.
    event ClaimFundingFees(
        address[] markets,
        address[] assets,
        uint256[] claimedAmounts
    );

    /// @notice Emitted when claiming collateral.
    /// @param market  The market collateral was claimed for.
    /// @param asset   The asset the collateral was claimed for.
    /// @param timeKey The time key the collateral was claimed for.
    event ClaimCollateral(address market, address asset, uint256 timeKey);

    /// @notice Emitted when assets are liquidated.
    /// @param liquidator The address of the account that initiated the liquidation and thus recieves the rebalance fee.
    /// @param asset      The asset that was liquidated.
    /// @param asset      The asset that was liquidated.
    /// @param usdcAmountIn The amount of assets recieved from the liquidation      The asset that was liquidated.
    event LiquidateAssets(
        address indexed liquidator,
        address indexed asset,
        uint256 amount,
        uint256 usdcAmountIn
    );

    /// @notice Emitted when a liquidation order is created in a market.
    /// @param liquidator The address of the account that initiated the liquidation and thus recieves the rebalance fee.
    /// @param market     The market the order was created in.
    /// @param order      The order that was created via GMX.
    /// @param orderKey   The key identifying the order.
    event LiquidatePosition(
        address indexed liquidator,
        address indexed market,
        IGmxV2OrderTypes.CreateOrderParams order,
        bytes32 orderKey
    );

    /// @notice Emitted when a position is releveraged.
    /// @param rebalancer The address of the account that initiated the rebalance and thus recieves the rebalance fee.
    /// @param market     The market the position is in.
    /// @param order      The order that was created via GMX.
    /// @param orderKey   The key identifying the order.
    event ReleveragePosition(
        address indexed rebalancer,
        address indexed market,
        IGmxV2OrderTypes.CreateOrderParams order,
        bytes32 orderKey
    );

    /// @notice Emitted when a position is swap rebalanced.
    /// @param rebalancer      The address of the account that initiated the rebalance and thus recieves the rebalance fee.
    /// @param market          The market the position is in.
    /// @param rebalanceAmount The amount of the `asset` that left the contract.
    /// @param usdcAmountIn    The amount of USDC recieved after the rebalance is complete.
    event SwapRebalancePosition(
        address indexed rebalancer,
        address indexed market,
        uint256 rebalanceAmount,
        uint256 usdcAmountIn
    );

    /// @notice Emitted when a position is rebalanced.
    /// @param rebalancer The address of the account that initiated the rebalance and thus recieves the rebalance fee.
    /// @param market     The market the position is in.
    /// @param order   The order that was created via GMX.
    /// @param orderKey   The key identifying the order.
    event RebalancePosition(
        address indexed rebalancer,
        address indexed market,
        IGmxV2OrderTypes.CreateOrderParams order,
        bytes32 orderKey
    );

    /// @notice Emitted when excess profit is withdrawn from a strategy account.
    /// @param market    The market being withdrawn from.
    /// @param recipient The address that assets were sent to.
    /// @param amount    The amount of the `shortToken` being withdrawn.
    event WithdrawProfit(
        address indexed market,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when long token assets are swapped for USDC by the strategy account owner.
    /// @param asset          The asset being swapped for.
    /// @param assetAmountOut The amount of the `asset` that left the contract.
    /// @param usdcAmountIn   The amount of USDC recieved after the swap is complete.
    event SwapAssets(
        address indexed asset,
        uint256 assetAmountOut,
        uint256 usdcAmountIn
    );

    /// @notice Emitted when the `AfterOrderExecution` callback method is hit.
    /// @param orderKey The key for the order.
    event OrderExecuted(bytes32 orderKey);

    /// @notice Emitted when the `AfterOrderExecution` callback method is hit.
    /// @param orderKey The key for the order.
    event OrderCancelled(bytes32 orderKey);

    // ============ Structs ============

    /// @dev The configuration for callbacks made through this strategy.
    struct CallbackConfig {
        // The address of the callback contract.
        address callback;
        // The address that the tokens should be sent to. In many cases it is more gas efficient for
        // the GoldLink Protocol to send tokens directly.
        address receiever;
        // The maximum tokens exchanged during the callback.
        uint256 tokenAmountMax;
    }

    // ============ External Functions ============

    /// @dev Create an order to increase a position's size. The account must have `collateralAmount` USDC in their account. Ensures delta neutrality on creation. Non-atomic.
    function executeCreateIncreaseOrder(
        address market,
        uint256 collateralAmount,
        uint256 executionFee
    )
        external
        payable
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 oderKey
        );

    /// @dev Create an order to decrease a position's size. Non-atomic.
    function executeCreateDecreaseOrder(
        address market,
        uint256 sizeDeltaUsd,
        uint256 executionFee
    )
        external
        payable
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        );

    /// @dev Cancels an order in a given market. Does not apply to liquidation orders.
    function executeCancelOrder(bytes32 orderKey) external;

    /// @dev Claim funding fees for the provided markets and assets. Fees are locked in the contract until the loan is repaid or they are used as collateral.
    function executeClaimFundingFees(
        address[] memory markets,
        address[] memory assets
    ) external;

    /// @dev Withdraw profit from a given market. Can only withdraw long tokens.
    function executeWithdrawProfit(
        WithdrawalLogic.WithdrawProfitParams memory params
    ) external;

    /// @dev Claim collateral in the event of a GMX collateral lock-up.
    function executeClaimCollateral(
        address market,
        address asset,
        uint256 timeKey
    ) external;

    /// @dev Atomically liquidate assets. can be called by anyone when an accounts `liquidationStatus` is `ACTIVE`. Caller recieves a fee for their service.
    function executeLiquidateAssets(
        address asset,
        uint256 amount,
        address callback,
        address receiever,
        bytes memory data
    ) external;

    /// @dev Liquidate a position by creating an order to reduce the position's size.  Non-atomic.
    function executeLiquidatePosition(
        address market,
        uint256 sizeDeltaUsd,
        uint256 executionFee
    )
        external
        payable
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        );

    /// @dev Releverage a position.
    function executeReleveragePosition(
        address market,
        uint256 sizeDeltaUSD,
        uint256 executionFee
    )
        external
        payable
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        );

    /// @dev Rebalanec a position with
    function executeSwapRebalance(
        address market,
        IGmxFrfStrategyAccount.CallbackConfig memory callbackConfig,
        bytes memory data
    ) external;

    /// @dev Rebalance a position that is outside of the configured delta range. Callable by anyone. The caller recieves a fee for their service.  Non-atomic.
    function executeRebalancePosition(
        address market,
        uint256 executionFee
    )
        external
        payable
        returns (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        );

    /// @dev Allows the account owner to sell assets for USDC in order to repay theirloan.
    function executeSwapAssets(
        address market,
        uint256 longTokenAmountOut,
        address callback,
        address receiver,
        bytes memory data
    ) external;

    /// @dev Call multiple methods in a single transaction without the need of a contract.
    function multicall(
        bytes[] calldata data
    ) external payable returns (bytes[] memory results);

    // ============ Public Functions ============

    /// @dev Get the value of the account in terms of USDC.
    function getAccountValue()
        external
        view
        returns (uint256 strategyAssetValue);
}

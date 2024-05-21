// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStrategyBank } from "./IStrategyBank.sol";
import { IStrategyController } from "./IStrategyController.sol";

/**
 * @title IStrategyAccount
 * @author GoldLink
 *
 * @dev Base interface for the strategy account.
 */
interface IStrategyAccount {
    // ============ Enums ============

    /// @dev The liquidation status of an account, if a multi-step liquidation is actively
    /// occurring or not.
    enum LiquidationStatus {
        // The account is not actively in a multi-step liquidation state.
        INACTIVE,
        // The account is actively in a multi-step liquidation state.
        ACTIVE
    }

    // ============ Events ============

    /// @notice Emitted when a liquidation is initiated.
    /// @param accountValue The value of the account, in terms of the `strategyAsset`, that was
    /// used to determine if the account was liquidatable.
    event InitiateLiquidation(uint256 accountValue);

    /// @notice Emitted when a liquidation is processed, which can occur once an account has been fully liquidated.
    /// @param executor The address of the executor that processed the liquidation, and the reciever of the execution premium.
    /// @param strategyAssetsBeforeLiquidation The amount of `strategyAsset` in the account before liquidation.
    /// @param strategyAssetsAfterLiquidation The amount of `strategyAsset` in the account after liquidation.
    event ProcessLiquidation(
        address indexed executor,
        uint256 strategyAssetsBeforeLiquidation,
        uint256 strategyAssetsAfterLiquidation
    );

    /// @notice Emitted when native assets are withdrawn.
    /// @param receiver The address the assets were sent to.
    /// @param amount   The amount of tokens sent.
    event WithdrawNativeAsset(address indexed receiver, uint256 amount);

    /// @notice Emitted when ERC-20 assets are withdrawn.
    /// @param receiver The address the assets were sent to.
    /// @param token    The ERC-20 token that was withdrawn.
    /// @param amount   The amount of tokens sent.
    event WithdrawErc20Asset(
        address indexed receiver,
        IERC20 indexed token,
        uint256 amount
    );

    // ============ External Functions ============

    /// @dev Initialize the account.
    function initialize(
        address owner,
        IStrategyController strategyController
    ) external;

    /// @dev Execute a borrow against the `strategyBank`.
    function executeBorrow(uint256 loan) external returns (uint256 loanNow);

    /// @dev Execute repaying a loan for an existing strategy bank.
    function executeRepayLoan(
        uint256 repayAmount
    ) external returns (uint256 loanNow);

    /// @dev Execute withdrawing collateral for an existing strategy bank.
    function executeWithdrawCollateral(
        address onBehalfOf,
        uint256 collateral,
        bool useSoftWithdrawal
    ) external returns (uint256 collateralNow);

    /// @dev Execute add collateral for the strategy account.
    function executeAddCollateral(
        uint256 collateral
    ) external returns (uint256 collateralNow);

    /// @dev Initiates an account liquidation, checking to make sure that the account's health score puts it in the liquidable range.
    function executeInitiateLiquidation() external;

    /// @dev Processes a liquidation, checking to make sure that all assets have been liquidated, and then notifying the `StrategyBank` of the liquidated asset's for accounting purposes.
    function executeProcessLiquidation()
        external
        returns (uint256 premium, uint256 loanLoss);

    /// @dev Get the positional value of the strategy account.
    function getAccountValue() external view returns (uint256);

    /// @dev Get the owner of this strategy account.
    function getOwner() external view returns (address owner);

    /// @dev Get the liquidation status of the account.
    function getAccountLiquidationStatus()
        external
        view
        returns (LiquidationStatus status);

    /// @dev Get address of strategy bank.
    function STRATEGY_BANK() external view returns (IStrategyBank strategyBank);

    /// @dev Get the GoldLink protocol asset.
    function STRATEGY_ASSET() external view returns (IERC20 strategyAsset);
}

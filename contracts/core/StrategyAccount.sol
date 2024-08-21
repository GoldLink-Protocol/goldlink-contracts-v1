// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Errors } from "../libraries/Errors.sol";
import { IStrategyController } from "../interfaces/IStrategyController.sol";
import { IStrategyAccount } from "../interfaces/IStrategyAccount.sol";
import { IStrategyBank } from "../interfaces/IStrategyBank.sol";

/**
 * @title StrategyAccount
 * @author GoldLink
 *
 * @dev Abstract contract for a borrower to engage with their loan, deploying
 * funds into upstreams, rebalancing positions, and managing PnL.
 */
abstract contract StrategyAccount is Initializable, IStrategyAccount {
    using SafeERC20 for IERC20;

    // ============ Storage Variables ============

    /// @dev The `StrategyAsset` for this strategy account.
    IERC20 private strategyAsset_;

    /// @dev The `StrategyController` for this strategy account.
    IStrategyController private strategyController_;

    /// @dev The `StrategyBank` associated with this strategy account.
    IStrategyBank private strategyBank_;

    /// @dev The owner of this strategy account.
    address private owner_;

    /// @dev The liquidation status of the account.
    LiquidationStatus private accountLiquidationStatus_;

    /**
     * @dev This is empty reserved space intended to allow future versions of this upgradeable
     *  contract to define new variables without shifting down storage in the inheritance chain.
     *  See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;

    // ============ Modifiers ============

    /// @dev Require sender is the owner of the strategy account.
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    /// @dev Verify the account is being liquidated.
    modifier whenLiquidating() {
        _whenLiquidating();
        _;
    }

    /// @dev Verify the account is not currently being liquidated.
    modifier whenNotLiquidating() {
        _whenNotLiquidating();
        _;
    }

    /// @dev Verify the account has an active loan.
    modifier hasActiveLoan() {
        _hasActiveLoan();
        _;
    }

    /// @dev Verify the account has no active loan.
    modifier noActiveLoan() {
        _noActiveLoan();
        _;
    }

    /// @dev Aquire a lock for the strategy.
    modifier strategyNonReentrant() {
        _acquireLock();
        _;
        _releaseLock();
    }

    /// @dev Make sure the account is not paused.
    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    // ============ Initializer ============

    function __StrategyAccount_init(
        address owner,
        IStrategyController strategyController
    ) internal onlyInitializing {
        __StrategyAccount_init_unchained(owner, strategyController);
    }

    function __StrategyAccount_init_unchained(
        address owner,
        IStrategyController strategyController
    ) internal onlyInitializing {
        // Set the `StrategyController`.
        strategyController_ = strategyController;

        // Set the `StrategyAsset`.
        strategyAsset_ = strategyController.STRATEGY_ASSET();

        // Set the `StrategyBank`.
        strategyBank_ = strategyController.STRATEGY_BANK();

        // Set ownership to the owner who will be the borrower going forward.
        owner_ = owner;

        // Approve the `StrategyBank` to spend the protocol asset.
        strategyAsset_.approve(
            address(strategyController.STRATEGY_BANK()),
            type(uint256).max
        );
    }

    // ============ Virtual Functions ============

    /**
     * @notice Required hook that evaluates the total value of the strategy account to determine whether or not the account is liquidatable.
     * Should return an integer value representing the total value of the strategy account in terms of the strategy's `strategyAsset`.
     * The value returned by this function should be representative of the amount of `strategyAsset` that can ultimately be used to repay account debts.
     * retrieved via an account liquidation.
     * @return valueInStrategyAsset The total value of the strategy account in terms of the strategy's `strategyAsset`.
     */
    function getAccountValue()
        public
        view
        virtual
        returns (uint256 valueInStrategyAsset);

    /**
     * @notice Optional hook that is called before a borrow occurs. This hook should be used to perform any checks/state updates that may be required before a borrow occurs.
     * @param requestedAmount The amount of assets the account owner requested to borrow.
     */
    function _beforeBorrow(uint256 requestedAmount) internal virtual {}

    /**
     * @notice Optional hook that is called after a borrow occurs. This hook should be used to perform any checks/state updates that may be required after a borrow occurs and lent assets are recieved.
     * @param amountBorrowed The amount of assets the account owner borrowed.
     */
    function _afterBorrow(uint256 amountBorrowed) internal virtual {}

    /**
     * @notice Optional hook that is called before a repay occurs. This hook should be used to perform any checks/state updates that may be required before repaying a loan.
     * @param repayAmount The amount of assets the account is attempting to repay.
     */
    function _beforeRepay(uint256 repayAmount) internal virtual {}

    /**
     * @notice Optional hook that is called after a repay occurs. This hook should be used to perform any checks/state updates that may be required after a repay occurs.
     */
    function _afterRepay() internal virtual {}

    /**
     * @notice Optional hook that is called before a liquidation is initiated. This hook should be used to perform any checks/state updates that may be required before a liquidation is initiated.
     */
    function _beforeInitiateLiquidation() internal virtual {}

    /**
     * @notice Optional hook that is called a liquidation is initiated. This hook should be used to perform any state updates that may be required after a liquidation is initiated. Possible actions to
     * take in this hook include selling off assets, cancelling orders, or creating liquidation orders.
     */
    function _afterInitiateLiquidation() internal virtual {}

    /**
     * @notice Optional hook that is called before a liquidation is processed. This hook should be used to perform any checks/state updates that may be required before a liquidation is processed.
     */
    function _beforeProcessLiquidation() internal virtual {}

    /**
     * @notice Optional hook that is called a liquidation is initiated. This hook should be used to perform any state updates that may be required after a liquidation is initiated. Possible actions to
     * take in this hook include selling off assets, cancelling orders, or creating liquidation orders.
     */
    function _afterProcessLiquidation(uint256 loanLoss) internal virtual {}

    /**
     * @notice Required hook that returns the total amount of `strategyAsset` that can be used to repay account debts.  This value should omit any `strategyAsset` that cannot be taken to repay debts.
     * Called during `executeProcessLiquidation` to let the bank know how many assets it can pull from the strategyAccount.
     * @return availableStrategyAssetAmount The amount of `strategyAsset` that can be used to repay account debts during the liquidation process.
     */
    function _getAvailableStrategyAsset()
        internal
        view
        virtual
        returns (uint256 availableStrategyAssetAmount);

    /**
     * @notice Required hook that validates an account has been fully liquidated and the bank should begin processing the liquidation. This implies all of the account's assets have been
     * exchanged for `strategyAsset`. This function should revert if the account still has assets that need to be liquidated.
     */
    function _isLiquidationFinished()
        internal
        view
        virtual
        returns (bool isFinished);

    // ============ External Functions ============

    /**
     * @notice Implements execute borrow, calling the `StrategyBank` to borrow funds
     * from the `STRATEGY_RESERVE` for this strategy account.
     * @param loan    The increase in the loan for the borrower balance.
     * @param loanNow The total loans outstanding for this account.
     */
    function executeBorrow(
        uint256 loan
    )
        external
        onlyOwner
        strategyNonReentrant
        whenNotLiquidating
        whenNotPaused
        returns (uint256 loanNow)
    {
        _beforeBorrow(loan);

        loanNow = strategyBank_.borrowFunds(loan);

        _afterBorrow(loan);

        return loanNow;
    }

    /**
     * @notice Implements execute repay loan, calling the `StrategyBank` to
     *  repay an existing loan for this strategy account.
     * @param repayAmount The amount of the base loan to sell off.
     * @return loanNow    The new loan amount after repayment.
     */
    function executeRepayLoan(
        uint256 repayAmount
    )
        external
        onlyOwner
        strategyNonReentrant
        whenNotLiquidating
        hasActiveLoan
        returns (uint256 loanNow)
    {
        _beforeRepay(repayAmount);

        loanNow = strategyBank_.repayLoan(repayAmount, getAccountValue());

        _afterRepay();

        return loanNow;
    }

    /**
     * @notice Implements execute withdraw collateral, calling the `StrategyBank` to withdraw
     * collateral from an existing loan for this strategy account.
     * @param onBehalfOf        The address receiving collateral.
     * @param collateral        The collateral being withdrawn.
     * @param useSoftWithdrawal If withdrawing should be skipped or revert if withdrawing is not possible.
     * Verified after handling loss, if withdrawing collateral would raise health score above maximum
     * open for the borrower.
     * @return collateralNow    The new collateral balance after withdrawing.
     */
    function executeWithdrawCollateral(
        address onBehalfOf,
        uint256 collateral,
        bool useSoftWithdrawal
    )
        external
        onlyOwner
        strategyNonReentrant
        whenNotLiquidating
        whenNotPaused
        returns (uint256 collateralNow)
    {
        return
            strategyBank_.withdrawCollateral(
                onBehalfOf,
                collateral,
                useSoftWithdrawal
            );
    }

    /**
     * @notice Implements execute add collateral, supply collateral to the `StrategyBank`
     * for this strategy account to borrow.
     * @param collateral     The amount of collateral being added.
     * @return collateralNow The new collateral balance after adding collateral.
     */
    function executeAddCollateral(
        uint256 collateral
    )
        external
        strategyNonReentrant
        whenNotLiquidating
        whenNotPaused
        returns (uint256 collateralNow)
    {
        return strategyBank_.addCollateral(msg.sender, collateral);
    }

    /**
     * @notice Initiates an account liquidation, first checking to make sure that the account's health score puts it in the liquidable range. Once a liquidation has been initiated,
     * strategy actions should be restricted until the liquidation has been completed and processed.
     */
    function executeInitiateLiquidation()
        external
        strategyNonReentrant
        whenNotLiquidating
        hasActiveLoan
        whenNotPaused
    {
        // Before initiate liquidation hook.
        _beforeInitiateLiquidation();

        uint256 accountValue = getAccountValue();

        require(
            strategyBank_.isAccountLiquidatable(address(this), accountValue),
            Errors.STRATEGY_ACCOUNT_ACCOUNT_IS_NOT_LIQUIDATABLE
        );

        // Set the account liquidation status to active.
        accountLiquidationStatus_ = LiquidationStatus.ACTIVE;

        emit InitiateLiquidation(accountValue);

        // After initiate liquidation hook.
        _afterInitiateLiquidation();
    }

    /**
     * @notice Processes a liquidation, first checking to make sure that all
     * assets have been liquidated, and then calling the `StrategyBank` to
     * process the liquidation.
     * @return premium  The executor premium awarded for liquidating the fully
     * unwound position.
     * @return loanLoss The loan loss incurred by lenders if the account was
     * underwater (liabilities in excess of assets).
     */
    function executeProcessLiquidation()
        external
        strategyNonReentrant
        whenLiquidating
        whenNotPaused
        returns (uint256 premium, uint256 loanLoss)
    {
        address liquidator = msg.sender;

        // Before process liquidation hook.
        _beforeProcessLiquidation();

        // Verify that the liquidation is finished.
        require(
            _isLiquidationFinished(),
            Errors.STRATEGY_ACCOUNT_CANNOT_PROCESS_LIQUIDATION_WHEN_NOT_COMPLETE
        );

        uint256 strategyAssetsBeforeLiquidation = _getAvailableStrategyAsset();

        // Process the liquidation.
        (premium, loanLoss) = strategyBank_.processLiquidation(
            liquidator,
            strategyAssetsBeforeLiquidation
        );

        // Set the account liquidation status to inactive.
        accountLiquidationStatus_ = LiquidationStatus.INACTIVE;

        emit ProcessLiquidation(
            liquidator,
            strategyAssetsBeforeLiquidation,
            _getAvailableStrategyAsset()
        );

        // After process liquidation hook.
        _afterProcessLiquidation(loanLoss);

        return (premium, loanLoss);
    }

    /**
     * @notice Withdraws native assets to the specified receiver.
     * Can only be called when the account has no active loan.
     * @dev Emits the `WithdrawNativeAsset()` event.
     * @param receiver The address to send the assets to.
     * @param amount   The amount to be withdrawn.
     */
    function executeWithdrawNativeAsset(
        address payable receiver,
        uint256 amount
    ) external onlyOwner strategyNonReentrant whenNotLiquidating noActiveLoan {
        receiver.transfer(amount);
        emit WithdrawNativeAsset(receiver, amount);
    }

    /**
     * @notice Withdraws ERC-20 assets to the specified receiver.
     * Can only be called when the account has no active loan.
     * @dev Emits the `WithdrawErc20Asset()` event.
     * @param receiever The address to send the assets to.
     * @param tokens    The ERC-20 tokens to be withdrawn.
     * @param amounts   The ERC-20 amounts to be withdrawn.
     */
    function executeWithdrawErc20Assets(
        address receiever,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external onlyOwner strategyNonReentrant whenNotLiquidating noActiveLoan {
        uint256 n = tokens.length;

        require(
            amounts.length == n,
            Errors.STRATEGY_ACCOUNT_PARAMETERS_LENGTH_MISMATCH
        );

        for (uint256 i; i < n; ++i) {
            if (amounts[i] > 0) {
                tokens[i].safeTransfer(receiever, amounts[i]);
            }
            emit WithdrawErc20Asset(receiever, tokens[i], amounts[i]);
        }
    }

    function STRATEGY_BANK() public view returns (IStrategyBank strategyBank) {
        return strategyBank_;
    }

    function STRATEGY_ASSET() public view returns (IERC20 strategyAsset) {
        return strategyAsset_;
    }

    /**
     * @notice Get the owner of this strategy account.
     *
     * @return owner The owner of this strategy account.
     */
    function getOwner() external view returns (address owner) {
        return owner_;
    }

    /**
     * @notice Get the liquidation status of the account.
     *
     * @return status The liquidation status of the account.
     */
    function getAccountLiquidationStatus()
        external
        view
        returns (LiquidationStatus status)
    {
        return accountLiquidationStatus_;
    }

    function _onlyOwner() private view {
        require(
            msg.sender == owner_,
            Errors.STRATEGY_ACCOUNT_SENDER_IS_NOT_OWNER
        );
    }

    function _whenLiquidating() private view {
        require(
            accountLiquidationStatus_ == LiquidationStatus.ACTIVE,
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_INACTIVE
        );
    }

    function _whenNotLiquidating() private view {
        require(
            accountLiquidationStatus_ == LiquidationStatus.INACTIVE,
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_ACTIVE
        );
    }

    function _hasActiveLoan() private view {
        require(
            strategyBank_.getStrategyAccountHoldings(address(this)).loan > 0,
            Errors.STRATEGY_ACCOUNT_ACCOUNT_HAS_NO_LOAN
        );
    }

    function _noActiveLoan() private view {
        require(
            strategyBank_.getStrategyAccountHoldings(address(this)).loan == 0,
            Errors.STRATEGY_ACCOUNT_ACCOUNT_HAS_AN_ACTIVE_LOAN
        );
    }

    function _acquireLock() private {
        strategyBank_.acquireLock();
    }

    function _releaseLock() private {
        strategyBank_.releaseLock();
    }

    function _whenNotPaused() private view {
        require(
            !strategyController_.isPaused(),
            Errors.CANNOT_CALL_FUNCTION_WHEN_PAUSED
        );
    }
}

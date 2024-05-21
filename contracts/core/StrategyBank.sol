// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Errors } from "../libraries/Errors.sol";
import { Constants } from "../libraries/Constants.sol";
import { PercentMath } from "../libraries/PercentMath.sol";
import { StrategyBankHelpers } from "../libraries/StrategyBankHelpers.sol";
import { IStrategyAccount } from "../interfaces/IStrategyAccount.sol";
import {
    IStrategyAccountDeployer
} from "../interfaces/IStrategyAccountDeployer.sol";
import { GoldLinkOwnable } from "../utils/GoldLinkOwnable.sol";
import { IStrategyBank } from "../interfaces/IStrategyBank.sol";
import { IStrategyReserve } from "../interfaces/IStrategyReserve.sol";
import { IStrategyController } from "../interfaces/IStrategyController.sol";
import { ControllerHelpers } from "./ControllerHelpers.sol";
import { StrategyController } from "../core/StrategyController.sol";

/**
 * @title StrategyBank
 * @author GoldLink
 *
 * @notice Holds strategy account collateral, manages loan accounting for
 * strategy accounts, manages liquidations, and pays interest on loan
 * balances to the strategy reserve.
 */
contract StrategyBank is IStrategyBank, GoldLinkOwnable, ControllerHelpers {
    using PercentMath for uint256;
    using SafeERC20 for IERC20;
    using StrategyBankHelpers for StrategyAccountHoldings;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Constants ============

    /// @notice The associated reserve where funds are borrowed from.
    IStrategyReserve public immutable STRATEGY_RESERVE;

    /// @notice The asset that is lent and borrowed for use with the strategy.
    IERC20 public immutable STRATEGY_ASSET;

    /// @notice The contract that deploys borrower accounts for this strategy.
    IStrategyAccountDeployer public immutable STRATEGY_ACCOUNT_DEPLOYER;

    /// @notice The portion of interest paid as a fee to the insurance fund
    /// (denoted in WAD).
    uint256 public immutable INSURANCE_PREMIUM;

    /// @notice The additional premium taken from remaining collateral when a
    /// liquidation occurs and set aside for insurance (denoted in WAD).
    uint256 public immutable LIQUIDATION_INSURANCE_PREMIUM;

    /// @notice The percent of the liquidation premium that goes to the
    /// executor who called `processLiquidation` (denoted in WAD).
    uint256 public immutable EXECUTOR_PREMIUM;

    /// @notice The health score at which point a strategy account becomes
    /// liquidatable. Health scores are denoted in WAD.
    uint256 public immutable LIQUIDATABLE_HEALTH_SCORE;

    /// @notice The minimum collateral amount that should be held by any
    /// account with an active loan. Operations may be blocked if they would
    /// violate this constraint.
    ///
    /// Note that the collateral in an account can still drop below this value
    /// due to accrued interest or account liquidation.
    uint256 public immutable MINIMUM_COLLATERAL_BALANCE;

    // ============ Storage Variables ============

    /// @notice The total collateral deposited in this contract. Any assets in
    /// this contract beyond `totalCollateral_` are treated as part of the
    /// insurance fund.
    ///
    /// It is possible for total collateral to deviate from the sum of borrower
    /// collateral in certain cases:
    ///  - Rounding errors
    ///  - Underwater borrower accounts
    uint256 public totalCollateral_;

    /// @notice The minimum health score a strategy account can actively take
    /// on. Operations may be blocked if they would violate this constraint.
    /// Health scores are denoted in WAD.
    uint256 public minimumOpenHealthScore_;

    /// @dev Set of all strategy accounts deployed by this bank.
    EnumerableSet.AddressSet internal strategyAccountsSet_;

    /// @dev Mapping of strategy accounts to their holdings in the strategy.
    mapping(address => StrategyAccountHoldings) internal strategyAccounts_;

    // ============ Modifiers ============

    /// @dev Require caller is a recognized strategy account deployed by the bank.
    modifier onlyValidStrategyAccount() {
        require(
            strategyAccountsSet_.contains(msg.sender),
            Errors.STRATEGY_BANK_CALLER_IS_NOT_VALID_STRATEGY_ACCOUNT
        );
        _;
    }

    /// @dev Require caller is the strategy reserve associated with this bank.
    modifier onlyStrategyReserve() {
        require(
            msg.sender == address(STRATEGY_RESERVE),
            Errors.STRATEGY_BANK_CALLER_MUST_BE_STRATEGY_RESERVE
        );
        _;
    }

    // ============ Constructor ============

    constructor(
        address strategyOwner,
        IERC20 strategyAsset,
        IStrategyController strategyController,
        IStrategyReserve strategyReserve,
        BankParameters memory parameters
    ) Ownable(strategyOwner) ControllerHelpers(strategyController) {
        // Strategy Account deployer cannot be zero address.
        require(
            address(parameters.strategyAccountDeployer) != address(0),
            Errors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );

        // Validate liquidatable health score is within valid range.
        require(
            parameters.liquidatableHealthScore > 0,
            Errors
                .STRATEGY_BANK_LIQUIDATABLE_HEALTH_SCORE_MUST_BE_GREATER_THAN_ZERO
        );
        require(
            parameters.liquidatableHealthScore < Constants.ONE_HUNDRED_PERCENT,
            Errors
                .STRATEGY_BANK_LIQUIDATABLE_HEALTH_SCORE_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT
        );

        // Cannot set `minimumOpenHealthScore` at or below `liquidatableHealthScore`.
        // There is no concern with an upper bounds as the protocol may want to lock out new engagement in a strategy with
        // a very high minimum open health score.
        require(
            parameters.minimumOpenHealthScore >
                parameters.liquidatableHealthScore,
            Errors
                .STRATEGY_BANK_MINIMUM_OPEN_HEALTH_SCORE_CANNOT_BE_AT_OR_BELOW_LIQUIDATABLE_HEALTH_SCORE
        );

        // All premiums must be less than one hundred percent.
        require(
            parameters.executorPremium < Constants.ONE_HUNDRED_PERCENT,
            Errors
                .STRATEGY_BANK_EXECUTOR_PREMIUM_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT
        );
        require(
            parameters.insurancePremium < Constants.ONE_HUNDRED_PERCENT,
            Errors
                .STRATEGY_BANK_INSURANCE_PREMIUM_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT
        );
        require(
            parameters.liquidationInsurancePremium <
                Constants.ONE_HUNDRED_PERCENT,
            Errors
                .STRATEGY_BANK_LIQUIDATION_INSURANCE_PREMIUM_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT
        );

        // Set immutable parameters.
        STRATEGY_ASSET = strategyAsset;
        STRATEGY_RESERVE = strategyReserve;
        INSURANCE_PREMIUM = parameters.insurancePremium;
        LIQUIDATION_INSURANCE_PREMIUM = parameters.liquidationInsurancePremium;
        EXECUTOR_PREMIUM = parameters.executorPremium;
        LIQUIDATABLE_HEALTH_SCORE = parameters.liquidatableHealthScore;
        MINIMUM_COLLATERAL_BALANCE = parameters.minimumCollateralBalance;
        STRATEGY_ACCOUNT_DEPLOYER = parameters.strategyAccountDeployer;

        // Set mutable parameters.
        minimumOpenHealthScore_ = parameters.minimumOpenHealthScore;

        // Set allowance for the `STRATEGY_RESERVE` to take allowed assets when repaying
        // loans.
        STRATEGY_ASSET.approve(address(STRATEGY_RESERVE), type(uint256).max);
    }

    // ============ External Functions ============

    /**
     * @notice Implements update minimum health score, modifying the minimum health
     * score a strategy account can actively take on.
     * @dev If `newMinimumOpenHealthScore = uint256.max` then the strategy has effectively
     * been paused.
     * @dev Emits the `UpdateMinimumOpenHealthScore()` event.
     * @param newMinimumOpenHealthScore The new minimum open health score.
     */
    function updateMinimumOpenHealthScore(
        uint256 newMinimumOpenHealthScore
    ) external onlyOwner {
        // Cannot set `minimumOpenHealthScore_` at or below the liquidation threshold.
        require(
            newMinimumOpenHealthScore > LIQUIDATABLE_HEALTH_SCORE,
            Errors
                .STRATEGY_BANK_MINIMUM_OPEN_HEALTH_SCORE_CANNOT_BE_AT_OR_BELOW_LIQUIDATABLE_HEALTH_SCORE
        );

        // Set new minimum open health score for this strategy bank.
        minimumOpenHealthScore_ = newMinimumOpenHealthScore;

        emit UpdateMinimumOpenHealthScore(newMinimumOpenHealthScore);
    }

    /**
     * @notice Implements acquire lock, acquiring the reentrancy lock for the strategy.
     * @dev IMPORTANT: The acquire and release functions are intended to be used as part of a
     * modifier to guarantee that the release function is always called at the end of a transaction
     * in which acquire has been called. This ensures that the value of `reentrancyStatus_` must be
     * `NOT_ENTERED` in between transactions.
     */
    function acquireLock() external onlyValidStrategyAccount {
        STRATEGY_CONTROLLER.acquireStrategyLock();
    }

    /**
     * @notice Implements release lock, releasing the reentrancy lock for the strategy.
     * @dev IMPORTANT: The acquire and release functions are intended to be used as part of a
     * modifier to guarantee that the release function is always called at the end of a transaction
     * in which acquire has been called. This ensures that the value of `reentrancyStatus_` must be
     * `NOT_ENTERED` in between transactions.
     */
    function releaseLock() external onlyValidStrategyAccount {
        STRATEGY_CONTROLLER.releaseStrategyLock();
    }

    /**
     * @notice Attempts to get interest for the reserve and take a haircut of insurance for the bank. Will potentially
     * be less than `totalRequested` if loan-loss occurred and the bank cannot send the full amount.
     * Will also attempt to withhold a haircut to grow the insurance fund.
     * @dev Insurance fund will attempt to offset lost interest in the case of insufficient collateral.
     * @dev Emits the `GetInterestAndTakeInsurance()` event.
     * @param totalRequested The interest requested by the `StrategyReserve` and insurance haircut.
     * @return interestToPay The interest to be paid to the strategy reserve after taking the insurance haircut.
     */
    function getInterestAndTakeInsurance(
        uint256 totalRequested
    ) external onlyStrategyReserve returns (uint256 interestToPay) {
        // Get bank balances.
        // The ERC-20 balance will always be at least `totalCollateral_`.
        uint256 erc20Balance = STRATEGY_ASSET.balanceOf(address(this));
        uint256 collateral = totalCollateral_;

        // Split interest into the portion for the reserve and for insurance.
        uint256 toInsurance = totalRequested.percentToFraction(
            INSURANCE_PREMIUM
        );
        uint256 toReserve = totalRequested - toInsurance;

        // Deduct from collateral first before insurance.
        // Determine the amount deducted from collateral.
        uint256 fromCollateral = Math.min(collateral, totalRequested);

        // Update total collateral in storage.
        totalCollateral_ = collateral - fromCollateral;

        // Pay the reserve, as much as is possible with collateral and insurance.
        interestToPay = Math.min(toReserve, erc20Balance);

        // Get for emit and return how much of the request was fulfilled.
        // Could potentially mean that insurance fund simply did not grow.
        uint256 interestAndInsurance = Math.min(totalRequested, erc20Balance);

        // If total requested does not equal `interestAndInsurance`, it means
        // insufficient collateral was available to pay interest due to the
        // borrow side of the protocol being underwater.
        //
        // This can only occur if at least one borrower is liquidatable due to
        // accumulated interest and not liquidated during the window of time
        // where the account's `collateral > interestOwed`.
        emit GetInterestAndTakeInsurance(
            totalRequested,
            fromCollateral,
            interestAndInsurance
        );

        return interestToPay;
    }

    /**
     * @notice Processes the completed liquidation of a strategy account.
     * Each strategy should ensure that this function is only callable once a
     * liquidation has been fully completed. The account should pass in the
     * quantity of `strategyAsset` that can be pulled from the account's
     * balance in order to repay liabilities.
     * @dev Emits the `LiquidateLoan()` event.
     * @param liquidator             The address performing the liquidation, who will receive the executor's premium
     * @param availableAccountAssets The amount of assets available to repay the account's liabilities.
     * @return executorPremium       The premium paid to the `liquidator`.
     * @return loanLoss              The loan loss passed on to lenders as a result of the liquidated account being underwater.
     */
    function processLiquidation(
        address liquidator,
        uint256 availableAccountAssets
    )
        external
        onlyValidStrategyAccount
        whenNotPaused
        returns (uint256 executorPremium, uint256 loanLoss)
    {
        address strategyAccount = msg.sender;

        // Get strategy account's holdings.
        StrategyAccountHoldings storage holdings = strategyAccounts_[
            strategyAccount
        ];

        // Update the strategy account's interest.
        _updateBorrowerInterest(holdings);

        // Process the liquidation by netting out the account's remaining
        // assets and liabilities and applying liquidation premiums.
        uint256 oldCollateral = holdings.collateral;
        uint256 updatedCollateral;
        (executorPremium, loanLoss, updatedCollateral) = _liquidate(
            strategyAccount,
            holdings,
            availableAccountAssets
        );

        // Reduce total collateral based on the change in collateral.
        // The updated collateral will always be at most the old collateral.
        totalCollateral_ -= oldCollateral - updatedCollateral;

        // Reduce collateral in holdings and clear loan and interest index.
        strategyAccounts_[strategyAccount] = StrategyAccountHoldings({
            collateral: updatedCollateral,
            loan: 0,
            interestIndexLast: 0
        });

        // Transfer executor premium to liquidator if nonzero.
        if (executorPremium > 0) {
            STRATEGY_ASSET.safeTransfer(liquidator, executorPremium);
        }

        emit LiquidateLoan(
            liquidator,
            strategyAccount,
            loanLoss,
            executorPremium
        );

        return (executorPremium, loanLoss);
    }

    /**
     * @notice Implements add collateral, adding collateral to a strategy account holdings.
     * @dev Emits the `AddCollateral()` event.
     * @param provider   The address providing the collateral.
     * @param collateral The collateral being added to the strategy account holdings.
     */
    function addCollateral(
        address provider,
        uint256 collateral
    )
        external
        onlyValidStrategyAccount
        whenNotPaused
        returns (uint256 collateralNow)
    {
        address strategyAccount = msg.sender;

        // Get old holdings.
        StrategyAccountHoldings storage holdings = strategyAccounts_[
            strategyAccount
        ];

        // If attempting to deposit zero assets, return early.
        if (collateral == 0) {
            return holdings.collateral;
        }

        // Update the strategy account's interest before doing anything else.
        _updateBorrowerInterest(holdings);

        // Calculate and validate the updated collateral balance.
        uint256 updatedCollateral = holdings.collateral + collateral;
        require(
            updatedCollateral >= MINIMUM_COLLATERAL_BALANCE,
            Errors.STRATEGY_BANK_COLLATERAL_WOULD_BE_LESS_THAN_MINIMUM
        );

        // Update account collateral.
        holdings.collateral = updatedCollateral;

        // Increase total collateral with new assets.
        totalCollateral_ += collateral;

        // Transfer collateral to strategy bank.
        STRATEGY_ASSET.safeTransferFrom(provider, address(this), collateral);

        emit AddCollateral(provider, strategyAccount, collateral);

        return updatedCollateral;
    }

    /**
     * @notice Implements borrow funds, sending funds from the `STRATEGY_RESERVE` to the `msg.sender` who is a
     * strategy account and updating utilization in the reserve associated with this strategy bank.
     * @dev Emits the `BorrowFunds()` event.
     * @param loan     The increase in the strategy account loan assets.
     * @return loanNow The total value of the account's full loan after borrowing.
     */
    function borrowFunds(
        uint256 loan
    )
        external
        onlyValidStrategyAccount
        whenNotPaused
        returns (uint256 loanNow)
    {
        address strategyAccount = msg.sender;

        // Get old holdings.
        StrategyAccountHoldings storage holdings = strategyAccounts_[
            strategyAccount
        ];

        // Update the strategy account's interest owed and interest index first.
        _updateBorrowerInterest(holdings);

        // Update the strategy account's loan amount.
        holdings.loan += loan;

        // Verify minimum health score would be respected.
        require(
            holdings.getHealthScore(
                IStrategyAccount(strategyAccount).getAccountValue() + loan
            ) >= minimumOpenHealthScore_,
            Errors
                .STRATEGY_BANK_HEALTH_SCORE_WOULD_FALL_BELOW_MINIMUM_OPEN_HEALTH_SCORE
        );

        // Borrow the loan amount from the strategy reserve.
        // Will revert if attempting to borrow beyond the available amount.
        STRATEGY_RESERVE.borrowAssets(strategyAccount, loan);

        emit BorrowFunds(strategyAccount, loan);

        return holdings.loan;
    }

    /**
     * @notice Implements repay loan, called when a strategy account repays a portion
     * of their loan. Will either address profit or loss. For profit, pay `STRATEGY_RESERVE`.
     * For loss, will take loss out of collateral before repaying. A strategy account is
     * incentivized to avoid liquidations as they will be paying a premium to liquidators.
     * @dev Will revert if the holdings are liquidatable. To avoid reverting when liquidatable,
     * add collateral before repaying.
     * @dev Emits the `RepayLoan()` event.
     * @param repayAmount  The loan assets being repaid.
     * @param accountValue The current value of the account.
     * @return loanNow     The new loan amount after repayment.
     */
    function repayLoan(
        uint256 repayAmount,
        uint256 accountValue
    ) external onlyValidStrategyAccount returns (uint256 loanNow) {
        address strategyAccount = msg.sender;

        // Get strategy account holdings.
        StrategyAccountHoldings storage holdings = strategyAccounts_[
            strategyAccount
        ];

        // Cannot reduce loan below zero.
        require(
            repayAmount <= holdings.loan,
            Errors.STRATEGY_BANK_CANNOT_REPAY_MORE_THAN_TOTAL_LOAN
        );

        // Update the strategy account's interest.
        _updateBorrowerInterest(holdings);

        // Repayments are not allowed while a strategy account is liquidatable.
        require(
            !isAccountLiquidatable(strategyAccount, accountValue),
            Errors.STRATEGY_BANK_CANNOT_REPAY_LOAN_WHEN_LIQUIDATABLE
        );

        // Get the portion of the repayment (if any) coming from collateral.
        // If nonzero, it means that collateral is being used to offset losses
        // incurred by the strategy account.
        uint256 collateralRepayment = repayAmount -
            Math.min(repayAmount, accountValue);

        if (collateralRepayment != 0) {
            // We know there is enough collateral because otherwise the
            // account would be underwater and liquidatable.
            holdings.collateral -= collateralRepayment;
            totalCollateral_ -= collateralRepayment;
        }

        // Reduce loan in holdings by total `repayAmount` as the portion of the strategy account
        // and potentially a portion of collateral are being transferred to the strategy reserve.
        // Since the account is not liquidatable, there is no concern that the `repayAmount`
        // will not be fully paid.
        holdings.loan -= repayAmount;

        // Repay loan portion (`repayAmount`) to strategy reserve.
        _repayAssets(
            repayAmount,
            repayAmount,
            strategyAccount,
            collateralRepayment
        );

        emit RepayLoan(strategyAccount, repayAmount, collateralRepayment);

        return holdings.loan;
    }

    /**
     * @notice Implements withdraw collateral, allowing a strategy account to withdraw
     * collateral from the strategy bank.
     * @dev Emits the `WithdrawCollateral()` event.
     * @param onBehalfOf        The address receiving the collateral.
     * @param requestedWithdraw The collateral the borrower wants withdrawn from the strategy bank.
     * @param useSoftWithdrawal If withdrawing should be skipped or revert if withdrawing is not possible.
     * Verified after handling loss, if withdrawing collateral would raise health score above maximum
     * open for the strategy account.
     */
    function withdrawCollateral(
        address onBehalfOf,
        uint256 requestedWithdraw,
        bool useSoftWithdrawal
    )
        external
        onlyValidStrategyAccount
        whenNotPaused
        returns (uint256 collateralNow)
    {
        address strategyAccount = msg.sender;

        // Get strategy account's holdings.
        StrategyAccountHoldings storage holdings = strategyAccounts_[
            strategyAccount
        ];

        // If attempting to withdraw zero assets, return early.
        if (requestedWithdraw == 0) {
            return holdings.collateral;
        }

        // Cannot reduce collateral below zero.
        require(
            holdings.collateral >= requestedWithdraw,
            Errors.STRATEGY_BANK_CANNOT_DECREASE_COLLATERAL_BELOW_ZERO
        );

        // Update the strategy account's interest before doing anything else.
        _updateBorrowerInterest(holdings);

        // This calculation intentionally does not take profit into account.
        uint256 withdrawableCollateral = getWithdrawableCollateral(
            strategyAccount
        );

        // If not using soft withdrawal, revert if collateral withdrawn would be
        // less than requested.
        require(
            useSoftWithdrawal || requestedWithdraw <= withdrawableCollateral,
            Errors
                .STRATEGY_BANK_REQUESTED_WITHDRAWAL_AMOUNT_EXCEEDS_AVAILABLE_COLLATERAL
        );

        // Only withdraw up to amount that will respect health factor of the account.
        uint256 collateralToWithdraw = Math.min(
            requestedWithdraw,
            withdrawableCollateral
        );

        // Get the value of the collateral after the withdrawal would be completed.
        uint256 updatedCollateral = holdings.collateral - collateralToWithdraw;

        // If the new account collateral would be non-zero, make sure that
        // the collateral balance would remain above the minimum threshold.
        if (collateralToWithdraw != holdings.collateral) {
            require(
                updatedCollateral >= MINIMUM_COLLATERAL_BALANCE,
                Errors.STRATEGY_BANK_COLLATERAL_WOULD_BE_LESS_THAN_MINIMUM
            );
        }

        // If collateral is being withdraw, update storage and execute transfer.
        if (collateralToWithdraw > 0) {
            holdings.collateral = updatedCollateral;
            totalCollateral_ -= collateralToWithdraw;
            STRATEGY_ASSET.safeTransfer(onBehalfOf, collateralToWithdraw);
        }

        emit WithdrawCollateral(
            strategyAccount,
            onBehalfOf,
            collateralToWithdraw
        );

        return updatedCollateral;
    }

    /**
     * @notice Implements execute open account, deploying a new account for `onBehalfOf` to use the strategy.
     * @dev Emits the `OpenAccount()` event.
     * @param onBehalfOf       The address owning the new strategy account.
     * @return strategyAccount The address of the new strategy account.
     */
    function executeOpenAccount(
        address onBehalfOf
    ) external strategyNonReentrant returns (address strategyAccount) {
        // Deploy strategy account.
        strategyAccount = STRATEGY_ACCOUNT_DEPLOYER.deployAccount(
            onBehalfOf,
            STRATEGY_CONTROLLER
        );

        // Add strategy account to set of strategy accounts.
        strategyAccountsSet_.add(strategyAccount);

        emit OpenAccount(strategyAccount, onBehalfOf);

        return strategyAccount;
    }

    /**
     * @notice Implements get strategy account holdings.
     * @param strategyAccount The address of the strategy account.
     * @return holdings       The strategy account's holdings.
     */
    function getStrategyAccountHoldings(
        address strategyAccount
    ) external view returns (StrategyAccountHoldings memory holdings) {
        return strategyAccounts_[strategyAccount];
    }

    // ============ Public Functions ============

    /**
     * @notice Checks if an account is liquidatable.
     * @param strategyAccount The account being evaluated to see if it is liquidatable.
     * @param accountValue    The current value of the account positions.
     * @return isLiquidatable If the account is liquidatable.
     */
    function isAccountLiquidatable(
        address strategyAccount,
        uint256 accountValue
    ) public view returns (bool isLiquidatable) {
        // Get strategy account's holdings after paying interest.
        StrategyAccountHoldings
            memory holdings = getStrategyAccountHoldingsAfterPayingInterest(
                strategyAccount
            );

        // Return if the strategy account is liquidatable.
        return
            holdings.getHealthScore(accountValue) <= LIQUIDATABLE_HEALTH_SCORE;
    }

    /**
     * @notice Implements get withdrawable collateral, the collateral that can
     * be taken out such that `minimumOpenHealthScore_` is still respected.
     * @param strategyAccount         The address associated with the strategy account holdings.
     * @return withdrawableCollateral The amount of collateral withdrawable.
     */
    function getWithdrawableCollateral(
        address strategyAccount
    ) public view returns (uint256 withdrawableCollateral) {
        StrategyAccountHoldings memory holdings = strategyAccounts_[
            strategyAccount
        ];

        // After accounting for potential loss due to any reduction in the value of the account.
        uint256 adjustedCollateral = holdings.getAdjustedCollateral(
            IStrategyAccount(strategyAccount).getAccountValue()
        );

        // Get the minimum collateral supported by this loan and given `minimumOpenHealthScore_`.
        uint256 minimumCollateral = holdings.loan.percentToFraction(
            minimumOpenHealthScore_
        );

        // If adjusted collateral is less than minimum collateral, no collateral can be withdrawn.
        if (adjustedCollateral < minimumCollateral) {
            return 0;
        }

        // Return how much collateral can be withdrawn such that `minimumOpenHealthScore_`
        // is respected.
        return adjustedCollateral - minimumCollateral;
    }

    /**
     * @notice Get a strategy account's holdings after collateral is impacted by interest.
     * @param strategyAccount The strategy account whose holdings are being queried.
     * @return holdings       The current value of the holdings with collateral deducted by interest owed.
     */
    function getStrategyAccountHoldingsAfterPayingInterest(
        address strategyAccount
    ) public view returns (StrategyAccountHoldings memory holdings) {
        // Get strategy account's holdings.
        holdings = strategyAccounts_[strategyAccount];

        // Get interest owed and update local holdings object with impact of interest owed being accounted for.
        (uint256 interestOwed, uint256 interestIndexNow) = STRATEGY_RESERVE
            .settleInterestView(holdings.loan, holdings.interestIndexLast);
        holdings.collateral -= Math.min(holdings.collateral, interestOwed);
        holdings.interestIndexLast = interestIndexNow;

        return holdings;
    }

    /**
     * @notice Get all strategy accounts from (inclusive) index `startIndex` to index (exlusive) `stopIndex`.
     * @param startIndex The starting index of the strategy account list.
     * @param stopIndex  The ending index of the strategy account list. If `stop` is either `0` or greater than the number of accounts, will return all remaining accounts.
     * @return accounts  List of strategy accounts within the bounds of the provided `startIndex` and `stopIndex` indicies.
     */
    function getStrategyAccounts(
        uint256 startIndex,
        uint256 stopIndex
    ) external view returns (address[] memory accounts) {
        // Cap the stop index to the distance between start and stop.
        uint256 len = strategyAccountsSet_.length();
        uint256 stopIndexActual = stopIndex;
        if (stopIndex == 0 || stopIndex > len) {
            stopIndexActual = len;
        }

        accounts = new address[](stopIndexActual - startIndex);
        for (uint256 i = startIndex; i < stopIndexActual; i++) {
            accounts[i - startIndex] = strategyAccountsSet_.at(i);
        }

        return accounts;
    }

    // ============ Internal Functions ============

    /**
     * @notice Finish processing a liquidation by netting out the account's
     * remaining assets and liabilities and applying liquidation premiums.
     * @param strategyAccount    The liquidated account.
     * @param holdings           The loan position of the account.
     * @param availableAssets    The assets available in the liquidated account.
     * @return executorPremium   The premium to be paid to the liquidator.
     * @return loanLoss          The loan loss that will be incurred by lenders.
     * @return updatedCollateral The remaining collateral after processing the liquidation.
     */
    function _liquidate(
        address strategyAccount,
        StrategyAccountHoldings memory holdings,
        uint256 availableAssets
    )
        internal
        returns (
            uint256 executorPremium,
            uint256 loanLoss,
            uint256 updatedCollateral
        )
    {
        // Calculate the loan loss that will be incurred either by lenders
        // or by the insurance fund.
        //
        // Loan loss is zero if the account's total assets exceeded liabilities.
        // Otherwise, the loss is the difference between assets and liabilities.
        loanLoss =
            holdings.loan -
            Math.min(holdings.loan, availableAssets + holdings.collateral);

        // If loan loss is non-zero, it implies liquidated assets + collateral
        // have been fully consumed to pay off the borrower's liabilities.
        // Therefore, the updated collateral will be zero. Otherwise,
        // collateral should be reduced by the difference in value between the
        // strategy account assets and liabilities.
        updatedCollateral = holdings.collateral;
        updatedCollateral -= (loanLoss != 0)
            ? updatedCollateral
            : holdings.loan - Math.min(holdings.loan, availableAssets);

        // Pay premiums out of collateral.
        // This is a no-op if collateral is zero.
        (updatedCollateral, executorPremium) = _getPremiums(
            updatedCollateral,
            availableAssets
        );

        // If loan loss occurred, use available insurance to offset it.
        if (loanLoss != 0) {
            uint256 totalBalance = STRATEGY_ASSET.balanceOf(address(this));
            uint256 availableInsurance = totalBalance -
                Math.min(totalBalance, totalCollateral_);

            // Offset loan loss with the insurance fund.
            loanLoss -= Math.min(loanLoss, availableInsurance);
        }

        // Subtract the insurance-adjusted loan loss from the loan amount to
        // get the net amount that will be paid back to lenders.
        uint256 amountToRepay = holdings.loan -
            Math.min(holdings.loan, loanLoss);

        // Calculate the portion of repayment coming out of collateral.
        uint256 fromCollateral = amountToRepay -
            Math.min(amountToRepay, availableAssets);

        // Update strategy reserve to reflect loss.
        _repayAssets(
            holdings.loan,
            amountToRepay,
            strategyAccount,
            fromCollateral
        );

        return (executorPremium, loanLoss, updatedCollateral);
    }

    /**
     * @notice Settle interest for a borrower by reducing collateral by the
     * owed amount.
     * @param holdings A storage ref to the strategy accounts holdings, which will
     * be written to with updated interest.
     */
    function _updateBorrowerInterest(
        StrategyAccountHoldings storage holdings
    ) internal {
        // Settle interest associated with the account, getting the unpaid
        // accrued amount due since the last settlement.
        (uint256 interestOwed, uint256 interestIndexNext) = STRATEGY_RESERVE
            .settleInterest(holdings.loan, holdings.interestIndexLast);

        // Cannot reduce collateral below zero. If there is insufficient
        // collateral to pay interest owed, it means that the account was not
        // liquidated in time.
        uint256 collateralToReduce = Math.min(
            holdings.collateral,
            interestOwed
        );

        // Write the updated collateral and interest index to the strategy account.
        //
        // Note that the corresponding update to totalCollateral_ occurs
        // separately, in getInterestAndTakeInsurance().
        holdings.collateral -= collateralToReduce;
        holdings.interestIndexLast = interestIndexNext;
    }

    /**
     * @notice Repay a loan to the reserve by calling its repay() function.
     * The `fromCollateral` represents the amount paid out of collateral
     * (or the insurance fund) and may be zero. The rest of the funds will be
     * taken out of the strategy account before executing repayment.
     * @param initialLoan     The size of the loan being repaid.
     * @param returnedLoan    The amount of the loan that will be returned, net of loan loss.
     * @param strategyAccount The strategy account repaying the loan.
     * @param fromCollateral  The amount taken out of collateral to pay toward the loan.
     */
    function _repayAssets(
        uint256 initialLoan,
        uint256 returnedLoan,
        address strategyAccount,
        uint256 fromCollateral
    ) internal {
        if (returnedLoan > fromCollateral) {
            uint256 accountAssetBalance = returnedLoan - fromCollateral;

            require(
                STRATEGY_ASSET.balanceOf(msg.sender) >= accountAssetBalance,
                Errors
                    .STRATEGY_BANK_CANNOT_REPAY_MORE_THAN_IS_IN_STRATEGY_ACCOUNT
            );

            STRATEGY_ASSET.safeTransferFrom(
                strategyAccount,
                address(this),
                accountAssetBalance
            );
        }

        STRATEGY_RESERVE.repay(initialLoan, returnedLoan);
    }

    /**
     * @notice Get liquidation/insurance premiums as well as collateral after paying premiums.
     * @dev Collateral is assumed to be already impacted by paying off loss.
     * @dev Both premiums can be zero if there is not enough remaining collateral, with
     * a preference on paying the liquidator.
     * @param collateral         The remaining collateral for the liquidated position.
     * @param availableAssets    The remaining assets in the loan associated with the liquidation.
     * @return updatedCollateral The collateral after paying premiums.
     * @return executorPremium   The premium paid to the executor.
     */
    function _getPremiums(
        uint256 collateral,
        uint256 availableAssets
    )
        internal
        view
        returns (uint256 updatedCollateral, uint256 executorPremium)
    {
        // Apply the executor premium: the fee earned by the liquidator,
        // calculated as a portion of the liquidated account value.
        //
        // Note that the premiums cannot exceed the collateral that is
        // available in the account.
        executorPremium = Math.min(
            availableAssets.percentToFraction(EXECUTOR_PREMIUM),
            collateral
        );
        updatedCollateral = collateral - executorPremium;

        // Apply the insurance premium: the fee accrued to the insurance fund,
        // calculated as a portion of the liquidated account value.
        updatedCollateral -= Math.min(
            availableAssets.percentToFraction(LIQUIDATION_INSURANCE_PREMIUM),
            updatedCollateral
        );

        return (updatedCollateral, executorPremium);
    }
}

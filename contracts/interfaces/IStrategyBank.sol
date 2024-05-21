// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStrategyReserve } from "./IStrategyReserve.sol";
import { IStrategyAccountDeployer } from "./IStrategyAccountDeployer.sol";

/**
 * @title IStrategyBank
 * @author GoldLink
 *
 * @dev Base interface for the strategy bank.
 */
interface IStrategyBank {
    // ============ Structs ============

    /// @dev Parameters for the strategy bank being created.
    struct BankParameters {
        // The minimum health score a strategy account can actively take on.
        uint256 minimumOpenHealthScore;
        // The health score at which point a strategy account becomes liquidatable.
        uint256 liquidatableHealthScore;
        // The executor premium for executing a completed liquidation.
        uint256 executorPremium;
        // The insurance premium for repaying a loan.
        uint256 insurancePremium;
        // The insurance premium for liquidations, slightly higher than the
        // `INSURANCE_PREMIUM`.
        uint256 liquidationInsurancePremium;
        // The minimum active balance of collateral a strategy account can have.
        uint256 minimumCollateralBalance;
        // The strategy account deployer that deploys new strategy accounts for borrowers.
        IStrategyAccountDeployer strategyAccountDeployer;
    }

    /// @dev Strategy account assets and liabilities representing value in the strategy.
    struct StrategyAccountHoldings {
        // Collateral funds.
        uint256 collateral;
        // Loan capital outstanding.
        uint256 loan;
        // Last interest index for the strategy account.
        uint256 interestIndexLast;
    }

    // ============ Events ============

    /// @notice Emitted when updating the minimum open health score.
    /// @param newMinimumOpenHealthScore The new minimum open health score.
    event UpdateMinimumOpenHealthScore(uint256 newMinimumOpenHealthScore);

    /// @notice Emitted when getting interest and taking insurance before any
    /// reserve state-changing action.
    /// @param totalRequested       The total requested by the strategy reserve and insurance.
    /// @param fromCollateral       The amount of the request that was taken from collateral.
    /// @param interestAndInsurance The interest and insurance paid by this bank. Will be less
    /// than requested if there is not enough collateral + insurance to pay.
    event GetInterestAndTakeInsurance(
        uint256 totalRequested,
        uint256 fromCollateral,
        uint256 interestAndInsurance
    );

    /// @notice Emitted when liquidating a loan.
    /// @param liquidator      The address that performed the liquidation and is
    /// receiving the premium.
    /// @param strategyAccount The address of the strategy account.
    /// @param loanLoss        The loss being sent to lenders.
    /// @param premium         The amount of funds paid to the liquidator from the strategy.
    event LiquidateLoan(
        address indexed liquidator,
        address indexed strategyAccount,
        uint256 loanLoss,
        uint256 premium
    );

    /// @notice Emitted when adding collateral for a strategy account.
    /// @param sender          The address adding collateral.
    /// @param strategyAccount The strategy account address the collateral is for.
    /// @param collateral      The amount of collateral being put up for the loan.
    event AddCollateral(
        address indexed sender,
        address indexed strategyAccount,
        uint256 collateral
    );

    /// @notice Emitted when borrowing funds for a strategy account.
    /// @param strategyAccount The address of the strategy account borrowing funds.
    /// @param loan            The size of the loan to borrow.
    event BorrowFunds(address indexed strategyAccount, uint256 loan);

    /// @notice Emitted when repaying a loan for a strategy account.
    /// @param strategyAccount The address of the strategy account paying back
    /// the loan.
    /// @param repayAmount     The loan assets being repaid.
    /// @param collateralUsed  The collateral used to repay part of the loan if loss occured.
    event RepayLoan(
        address indexed strategyAccount,
        uint256 repayAmount,
        uint256 collateralUsed
    );

    /// @notice Emitted when withdrawing collateral.
    /// @param strategyAccount The address maintaining the strategy account's holdings.
    /// @param onBehalfOf      The address receiving the collateral.
    /// @param collateral      The collateral being withdrawn from the strategy bank.
    event WithdrawCollateral(
        address indexed strategyAccount,
        address indexed onBehalfOf,
        uint256 collateral
    );

    /// @notice Emitted when a strategy account is opened.
    /// @param strategyAccount The address of the strategy account.
    /// @param owner           The address of the strategy account owner.
    event OpenAccount(address indexed strategyAccount, address indexed owner);

    // ============ External Functions ============

    /// @dev Update the minimum open health score for the strategy bank.
    function updateMinimumOpenHealthScore(
        uint256 newMinimumOpenHealthScore
    ) external;

    /// @dev Delegates reentrancy locking to the bank, only callable by valid strategy accounts.
    function acquireLock() external;

    /// @dev Delegates reentrancy unlocking to the bank, only callable by valid strategy accounts.
    function releaseLock() external;

    /// @dev Get interest from this contract for `msg.sender` which must
    /// be the `StrategyReserve` to then transfer out of this contract.
    function getInterestAndTakeInsurance(
        uint256 totalRequested
    ) external returns (uint256 interestToPay);

    /// @dev Processes a strategy account liquidation.
    function processLiquidation(
        address liquidator,
        uint256 availableAccountAssets
    ) external returns (uint256 premium, uint256 loanLoss);

    /// @dev Add collateral for a strategy account into the strategy bank.
    function addCollateral(
        address provider,
        uint256 collateral
    ) external returns (uint256 collateralNow);

    /// @dev Borrow funds from the `StrategyReserve` into the strategy bank.
    function borrowFunds(uint256 loan) external returns (uint256 loanNow);

    /// @dev Repay loaned funds for a holdings.
    function repayLoan(
        uint256 repayAmount,
        uint256 accountValue
    ) external returns (uint256 loanNow);

    /// @dev Withdraw collateral from the strategy bank.
    function withdrawCollateral(
        address onBehalfOf,
        uint256 requestedWithdraw,
        bool useSoftWithdrawal
    ) external returns (uint256 collateralNow);

    /// @dev Open a new strategy account associated with `owner`.
    function executeOpenAccount(
        address owner
    ) external returns (address strategyAccount);

    /// @dev The strategy account deployer that deploys new strategy accounts for borrowers.
    function STRATEGY_ACCOUNT_DEPLOYER()
        external
        view
        returns (IStrategyAccountDeployer strategyAccountDeployer);

    /// @dev Strategy reserve address.
    function STRATEGY_RESERVE()
        external
        view
        returns (IStrategyReserve strategyReserve);

    /// @dev The asset that this strategy uses for lending accounting.
    function STRATEGY_ASSET() external view returns (IERC20 strategyAsset);

    /// @dev Get the minimum open health score.
    function minimumOpenHealthScore_()
        external
        view
        returns (uint256 minimumOpenHealthScore);

    /// @dev Get the liquidatable health score.
    function LIQUIDATABLE_HEALTH_SCORE()
        external
        view
        returns (uint256 liquidatableHealthScore);

    /// @dev Get the executor premium.
    function EXECUTOR_PREMIUM() external view returns (uint256 executorPremium);

    /// @dev Get the liquidation premium.
    function LIQUIDATION_INSURANCE_PREMIUM()
        external
        view
        returns (uint256 liquidationInsurancePremium);

    /// @dev Get the insurance premium.
    function INSURANCE_PREMIUM()
        external
        view
        returns (uint256 insurancePremium);

    /// @dev Get the total collateral deposited.
    function totalCollateral_() external view returns (uint256 totalCollateral);

    /// @dev Get a strategy account's holdings.
    function getStrategyAccountHoldings(
        address strategyAccount
    )
        external
        view
        returns (StrategyAccountHoldings memory strategyAccountHoldings);

    /// @dev Get withdrawable collateral such that it can be taken out while
    /// `minimumOpenHealthScore_` is still respected.
    function getWithdrawableCollateral(
        address strategyAccount
    ) external view returns (uint256 withdrawableCollateral);

    /// @dev Check if a position is liquidatable.
    function isAccountLiquidatable(
        address strategyAccount,
        uint256 positionValue
    ) external view returns (bool isLiquidatable);

    /// @dev Get strategy account's holdings after interest is paid.
    function getStrategyAccountHoldingsAfterPayingInterest(
        address strategyAccount
    ) external view returns (StrategyAccountHoldings memory holdings);

    /// @dev Get list of strategy accounts within two provided indicies.
    function getStrategyAccounts(
        uint256 startIndex,
        uint256 stopIndex
    ) external view returns (address[] memory accounts);
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { ProtocolDeployer } from "./ProtocolDeployer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IStrategyAccount } from "../contracts/interfaces/IStrategyAccount.sol";
import { IStrategyBank } from "../contracts/interfaces/IStrategyBank.sol";
import { IStrategyReserve } from "../contracts/interfaces/IStrategyReserve.sol";
import { TestUtilities } from "./testLibraries/TestUtilities.sol";
import { StrategyAccountMock } from "./mocks/StrategyAccountMock.sol";
import { PercentMath } from "../contracts/libraries/PercentMath.sol";
import { Constants } from "../contracts/libraries/Constants.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { StrategyReserve } from "../contracts/core/StrategyReserve.sol";
import "forge-std/Test.sol";

contract StateManager is Test, ProtocolDeployer {
    using PercentMath for uint256;

    // ============ Constants ============

    bool immutable SKIP_VALIDATIONS;

    // ============ Storage Variables ============

    uint64 private _accountLiquidationNonce = 1;

    // ============ Structs ============

    /// All relevant balances impacted by state change.
    /// @dev Necessary when state change leads to more than just a single transfer.
    struct AddressBalances {
        uint256 sender;
        uint256 strategyReserve;
        uint256 strategyBank;
        uint256 strategyAccount;
    }

    struct ExpectedLiquidationValues {
        uint256 expectedRepayAmount;
        uint256 expectedLoanLoss;
        uint256 expectedPremium;
        uint256 expectedInterestPaid;
        uint256 expectedCollateralRemaining;
        int256 expectedInsuranceDelta;
        uint256 expectedInsuranceFromInterest;
    }

    struct ExpectedRepayLoanValues {
        uint256 amount;
        uint256 assetChange;
        bool isProfit;
        uint256 interestAddressed;
        uint256 interestOwed;
        uint256 interestIndexNext;
        uint256 cumulativeInterestIndex;
        bool interestAlreadySent;
    }

    // ============ Events ============

    // Strategy Reserve

    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event BorrowAssets(uint256 borrowAmount);

    event Repay(uint256 initialLoan, uint256 returnedLoan);

    // Strategy Bank

    event LiquidateLoan(
        address indexed liquidator,
        address indexed strategyAccount,
        uint256 loanLoss,
        uint256 premium
    );

    event BorrowFunds(address indexed strategyAccount, uint256 loan);

    event AddCollateral(
        address indexed sender,
        address indexed strategyAccount,
        uint256 collateral
    );

    event RepayLoan(
        address indexed strategyAccount,
        uint256 loanRepaid,
        uint256 collateralUsed
    );

    event WithdrawCollateral(
        address indexed strategyAccount,
        address indexed onBehalfOf,
        uint256 collateral
    );

    // Liquidation Premium Manager.

    event ClaimPremium(
        address indexed claimer,
        address indexed strategyAccount,
        uint256 premium
    );

    // Strategy Account

    event TransferProfit(address indexed onBehalfOf, uint256 profit);

    // ============ Constructor ============

    constructor(bool skipValidations) ProtocolDeployer(false) {
        SKIP_VALIDATIONS = skipValidations;
    }

    // ============ Internal Functions ============

    // Protocol Owner Actions.

    // User Actions.

    /**
     * Validations:
     * 1. Lender shares were zero.
     * 2. Deposit as lender events fired as expected.
     * 3. Lender shares are as expected after lending.
     * 4. Lender transferred assets to reserve.
     */
    function _createLender(
        uint256 index,
        uint256 amount,
        uint256 expectedShares
    ) internal {
        // Update state for PNL
        _refreshState(index);

        IStrategyReserve reserve = strategyReserves[index];

        TestUtilities.mintAndApprove(usdc, amount, address(reserve));

        assertEq(reserve.balanceOf(msg.sender), 0, "New Lender shares != 0.");

        uint256 oldReserveBalance = usdc.balanceOf(address(reserve));
        uint256 oldSenderBalance = usdc.balanceOf(address(this));

        _expectEmitDeposit(
            index,
            address(this),
            msg.sender,
            amount,
            expectedShares
        );
        uint256 shares = reserve.deposit(amount, msg.sender);

        if (SKIP_VALIDATIONS) {
            return;
        }

        assertEq(
            reserve.balanceOf(msg.sender),
            expectedShares,
            "Reserve token ERC-20 balance != expected"
        );
        assertEq(shares, expectedShares, "Lender shares != expected");

        _validateAssetTransfer(
            address(this),
            address(reserve),
            oldSenderBalance,
            oldReserveBalance,
            amount
        );
    }

    /**
     * Validations:
     * 1. Increase lender events fired as expected.
     * 2. Shares cost as expected.
     * 3. Lender total shares as expected.
     * 4. Lender transferred assets to the strategy reserve.
     */
    function _increasePosition(
        uint256 index,
        uint256 expectedAmount,
        uint256 shares
    ) internal {
        // Update state for PNL
        _refreshState(index);

        IStrategyReserve reserve = strategyReserves[index];

        TestUtilities.mintAndApprove(usdc, expectedAmount, address(reserve));

        uint256 oldReserveBalance = usdc.balanceOf(address(reserve));
        uint256 oldSenderBalance = usdc.balanceOf(address(this));
        uint256 oldLenderShares = reserve.balanceOf(msg.sender);

        _expectEmitDeposit(
            index,
            address(this),
            msg.sender,
            expectedAmount,
            shares
        );
        uint256 amount = reserve.mint(shares, msg.sender);

        if (SKIP_VALIDATIONS) {
            return;
        }

        assertEq(amount, expectedAmount, "Lender mint != expected amount");

        assertEq(
            reserve.balanceOf(msg.sender),
            oldLenderShares + shares,
            "Lender shares != expected"
        );

        _validateAssetTransfer(
            address(this),
            address(reserve),
            oldSenderBalance,
            oldReserveBalance,
            expectedAmount
        );
    }

    /**
     * Validations:
     * 1. Decrease lender events fired as expected.
     * 2. Lender shares decreased as expected.
     * 3. Reserve transferred assets to lender.
     */
    function _reduceLenderPosition(
        uint256 index,
        uint256 amount,
        uint256 expectedShares
    ) internal {
        // Update state for PNL
        _refreshState(index);

        IStrategyReserve reserve = strategyReserves[index];

        uint256 oldReserveBalance = usdc.balanceOf(address(reserve));
        uint256 oldSenderBalance = usdc.balanceOf(msg.sender);
        uint256 oldLenderShares = reserve.balanceOf(msg.sender);

        _expectEmitWithdraw(
            index,
            msg.sender,
            msg.sender,
            msg.sender,
            amount,
            expectedShares
        );
        uint256 shares = reserve.withdraw(amount, msg.sender, msg.sender);

        if (SKIP_VALIDATIONS) {
            return;
        }

        assertEq(
            reserve.balanceOf(msg.sender),
            oldLenderShares - shares,
            "Reserve token ERC-20 balance != expected"
        );
        assertEq(shares, expectedShares, "Lender shares != expected");

        _validateAssetTransfer(
            address(reserve),
            msg.sender,
            oldReserveBalance,
            oldSenderBalance,
            amount
        );
    }

    /**
     * Validations:
     * 1. Decrease lender events fired as expected.
     * 2. Lender shares priced as expected.
     * 3. Reserve transferred assets to lender.
     */
    function _redeemLenderPosition(
        uint256 index,
        uint256 expectedAmount,
        uint256 shares
    ) internal {
        // Update state for PNL
        _refreshState(1);

        IStrategyReserve reserve = strategyReserves[index];

        uint256 oldReserveBalance = usdc.balanceOf(address(reserve));
        uint256 oldSenderBalance = usdc.balanceOf(msg.sender);
        uint256 oldLenderShares = reserve.balanceOf(msg.sender);

        _expectEmitWithdraw(
            index,
            msg.sender,
            msg.sender,
            msg.sender,
            expectedAmount,
            shares
        );
        uint256 amount = reserve.redeem(shares, msg.sender, msg.sender);

        if (SKIP_VALIDATIONS) {
            return;
        }

        assertEq(amount, expectedAmount, "Lender mint != expected amount");

        assertEq(
            reserve.balanceOf(msg.sender),
            oldLenderShares - shares,
            "Lender shares != expected"
        );

        _validateAssetTransfer(
            address(reserve),
            msg.sender,
            oldReserveBalance,
            oldSenderBalance,
            amount
        );
    }

    // Strategy

    /**
     * Validations:
     * 1. Liquidate events fired as expected.
     * 2. Premium was expected value.
     * 3. All holdings are reset except for reduced collateral.
     * 4. Sender balance updated with executor premium.
     * 5. Liquidator granted execution premium.
     * 6. Reserve balance after loan loss.
     * 7. Strategy account balance has been updated.
     * 8. Insurance fund has been updated.
     * 9. Strategy bank balance updated.
     * 10. Reserve updated.
     * 11. Liquidation manager updated.
     */
    function _liquidate(
        uint256 id,
        uint256 reserveIndex,
        ExpectedLiquidationValues memory expectedValues
    ) internal {
        IStrategyBank strategyBank = strategyAccounts[id].STRATEGY_BANK();

        IStrategyReserve reserve = strategyReserves[reserveIndex];

        AddressBalances memory oldBalances = AddressBalances({
            sender: usdc.balanceOf(address(this)),
            strategyAccount: usdc.balanceOf(address(strategyAccounts[id])),
            strategyReserve: usdc.balanceOf(address(reserve)),
            strategyBank: usdc.balanceOf(address(strategyBank))
        });

        IStrategyBank.StrategyAccountHoldings
            memory oldHoldings = _getStrategyAccountHoldings(id);

        uint256 oldInsurance = TestUtilities.getInsuranceFund(
            strategyBank,
            usdc
        );

        uint256 oldUtilizedAssets = reserve.utilizedAssets_();

        strategyAccounts[id].executeInitiateLiquidation();

        _expectEmitRepay(
            address(reserve),
            oldHoldings.loan,
            expectedValues.expectedRepayAmount
        );
        _expectEmitLiquidateLoan(
            address(strategyBank),
            address(this),
            address(strategyAccounts[id]),
            expectedValues.expectedLoanLoss,
            expectedValues.expectedPremium
        );
        (uint256 premium, ) = strategyAccounts[id].executeProcessLiquidation();

        if (SKIP_VALIDATIONS) {
            return;
        }

        assertEq(
            premium,
            expectedValues.expectedPremium,
            "Premium != expected."
        );

        _validateHoldings(
            id,
            IStrategyBank.StrategyAccountHoldings({
                loan: 0,
                interestIndexLast: oldHoldings.interestIndexLast,
                collateral: expectedValues.expectedCollateralRemaining
            })
        );

        if (premium > 0) {
            assertEq(
                usdc.balanceOf(address(this)),
                oldBalances.sender + premium,
                "Sender balance != expected after premium."
            );
        }

        assertEq(
            usdc.balanceOf(address(reserve)),
            oldBalances.strategyReserve +
                expectedValues.expectedInterestPaid +
                expectedValues.expectedRepayAmount -
                expectedValues.expectedInsuranceFromInterest,
            "Strategy reserve balance != expected."
        );

        uint256 strategyAccountBalance = oldBalances.strategyAccount -
            Math.min(oldBalances.strategyAccount, oldHoldings.loan);
        assertEq(
            usdc.balanceOf(address(strategyAccounts[id])),
            strategyAccountBalance,
            "Strategy account != expected."
        );

        _getLiquidationImpactOnStrategyBankBalance(
            expectedValues.expectedInsuranceDelta,
            strategyBank,
            oldInsurance,
            oldBalances.strategyBank,
            expectedValues.expectedCollateralRemaining,
            oldHoldings.collateral
        );

        assertEq(
            reserve.utilizedAssets_(),
            oldUtilizedAssets - oldHoldings.loan,
            "Post-liquidation utilization != expected."
        );

        _accountLiquidationNonce++;
    }

    /**
     * Validations:
     * 1. Add collateral events fired as expected.
     * 2. Assets transferred from borrow to strategy bank.
     * 3. Borrow holdings have been updated for borrower.
     */
    function _addCollateral(uint256 id, uint256 amount) internal {
        IStrategyAccount strategyAccount = strategyAccounts[id];
        IStrategyBank strategyBank = strategyAccount.STRATEGY_BANK();

        // Update state of the world - reflecting interest owed into the account.
        vm.prank(strategyAccount.getOwner());
        strategyAccount.executeBorrow(0);

        TestUtilities.mintAndApprove(usdc, amount, address(strategyBank));

        uint256 oldSenderBalance = usdc.balanceOf(address(this));
        uint256 oldStrategyBankBalance = usdc.balanceOf(address(strategyBank));
        IStrategyBank.StrategyAccountHoldings
            memory oldHoldings = _getStrategyAccountHoldings(id);

        if (amount > 0) {
            _expectEmitAddCollateral(
                address(strategyBank),
                address(this),
                address(strategyAccount),
                amount
            );
        }
        strategyAccount.executeAddCollateral(amount);

        if (SKIP_VALIDATIONS) {
            return;
        }

        _validateAssetTransfer(
            address(this),
            address(strategyBank),
            oldSenderBalance,
            oldStrategyBankBalance,
            amount
        );

        // Verify correct change in holdings where only change is amount increased.
        oldHoldings.collateral += amount;
        _validateHoldings(id, oldHoldings);
    }

    /**
     * Validations:
     * 1. Borrow events fired as expected.
     * 2. Assets transferred from the strategy reserve to strategy account.
     * 3. Borrow holdings have been updated for borrower.
     * 4. Reserve utilization has been updated as expected.
     */
    function _borrow(uint256 id, uint256 amount) internal {
        IStrategyAccount strategyAccount = strategyAccounts[id];
        IStrategyBank strategyBank = strategyAccount.STRATEGY_BANK();

        StrategyReserve reserve = StrategyReserve(
            address(strategyBank.STRATEGY_RESERVE())
        );

        // Update state of the world.
        strategyAccount.executeBorrow(0);

        uint256 oldUtilizedAssets = reserve.utilizedAssets_();
        uint256 oldStrategyAccountBalance = usdc.balanceOf(
            address(strategyAccount)
        );
        uint256 oldStrategyReserveBalance = usdc.balanceOf(address(reserve));
        IStrategyBank.StrategyAccountHoldings
            memory oldHoldings = _getStrategyAccountHoldings(id);

        _expectEmitBorrowAssets(address(reserve), amount);
        _expectEmitBorrowFunds(
            address(strategyBank),
            address(strategyAccount),
            amount
        );
        uint256 loanNow = strategyAccount.executeBorrow(amount);

        if (SKIP_VALIDATIONS) {
            return;
        }

        _validateAssetTransfer(
            address(reserve),
            address(strategyAccount),
            oldStrategyReserveBalance,
            oldStrategyAccountBalance,
            amount
        );

        // Verify correct change in holdings where loan and potential interest index changed.
        oldHoldings.loan += amount;
        _validateHoldings(id, oldHoldings);
        assertEq(oldHoldings.loan, loanNow);

        // Only change is to amount utilized inside.
        assertEq(
            reserve.utilizedAssets_(),
            oldUtilizedAssets + amount,
            "Post-borrow utilization != expected."
        );
    }

    /**
     * Validations:
     * 1. Repay events fired as expected.
     * 2. Borrow holdings have been updated for borrower.
     * 3. Reserve utilization has been updated as expected.
     * 4. Strategy account balance decreased.
     * 5. Sender account balance increased if there was profit.
     * 6. Treasury balance increased if there was profit.
     * 7. Reserve properly updated.
     * 8. Strategy bank updated if there was loss.
     */
    function _repayLoan(
        uint256 id,
        ExpectedRepayLoanValues memory expectedValues
    ) internal {
        IStrategyAccount strategyAccount = strategyAccounts[id];

        IStrategyBank strategyBank = strategyAccount.STRATEGY_BANK();

        StrategyReserve reserve = StrategyReserve(
            address(strategyBank.STRATEGY_RESERVE())
        );

        AddressBalances memory oldBalances = AddressBalances({
            sender: usdc.balanceOf(address(this)),
            strategyAccount: usdc.balanceOf(address(strategyAccount)),
            strategyReserve: usdc.balanceOf(address(reserve)),
            strategyBank: usdc.balanceOf(address(strategyBank))
        });

        uint256 oldUtilizedAssets = reserve.utilizedAssets_();

        IStrategyBank.StrategyAccountHoldings
            memory oldHoldings = _getStrategyAccountHoldings(id);

        _expectEmitRepay(
            address(reserve),
            expectedValues.amount,
            expectedValues.amount
        );
        _expectEmitRepayLoan(
            address(strategyBank),
            address(strategyAccount),
            expectedValues.amount,
            expectedValues.assetChange,
            expectedValues.isProfit
        );
        uint256 loanNow = strategyAccount.executeRepayLoan(
            expectedValues.amount
        );

        if (SKIP_VALIDATIONS) {
            return;
        }

        // Reduce by loss if needed and then by interest up to what is possible.
        uint256 collateralReduction = expectedValues.isProfit
            ? 0
            : expectedValues.assetChange;
        collateralReduction = Math.min(
            oldHoldings.collateral,
            collateralReduction + expectedValues.interestAddressed
        );

        // Verify correct change in holdings.
        oldHoldings.loan -= expectedValues.amount;
        oldHoldings.collateral -= collateralReduction;
        oldHoldings.interestIndexLast = expectedValues.interestIndexNext;
        _validateHoldings(id, oldHoldings);
        assertEq(oldHoldings.loan, loanNow);

        assertEq(
            reserve.utilizedAssets_(),
            oldUtilizedAssets - expectedValues.amount,
            "Post-repay utilization != expected."
        );
        assertEq(
            reserve.cumulativeInterestIndex(),
            expectedValues.cumulativeInterestIndex,
            "Interest index != expected."
        );

        // Validate balance changes.
        uint256 transferAmount = expectedValues.amount;
        if (expectedValues.isProfit) {
            transferAmount += expectedValues.assetChange;
        } else {
            transferAmount -= expectedValues.assetChange;
        }

        // If interest has been sent in a prior state-change, collateral is updated
        // but the reserve balance is not.
        uint256 interestSent = expectedValues.interestAlreadySent
            ? 0
            : expectedValues.interestAddressed;

        assertEq(
            usdc.balanceOf(address(reserve)),
            oldBalances.strategyReserve + expectedValues.amount + interestSent,
            "Strategy reserve balance != expected."
        );
        assertEq(
            usdc.balanceOf(address(strategyBank)),
            oldBalances.strategyBank -
                (expectedValues.isProfit ? 0 : expectedValues.assetChange),
            "Strategy bank balance != expected."
        );
    }

    /**
     * Validations:
     * 1. Withdraw events fired as expected.
     * 2. Borrow holdings have been updated for borrower.
     * 3. Transfer of assets, less insurance, from bank to sender.
     * 4. Insurance fund has increased.
     */
    function _withdrawCollateral(
        uint256 id,
        uint256 amount,
        bool isSoftWithdraw
    ) internal {
        IStrategyAccount strategyAccount = strategyAccounts[id];

        IStrategyBank strategyBank = strategyAccount.STRATEGY_BANK();

        // Update state of the world.
        strategyAccount.executeBorrow(0);

        uint256 oldStrategyBankBalance = usdc.balanceOf(address(strategyBank));
        uint256 oldSenderBalance = usdc.balanceOf(address(this));

        IStrategyBank.StrategyAccountHoldings
            memory oldHoldings = _getStrategyAccountHoldings(id);

        // Even if not allowing soft-withdrawal, assume not reverting.
        uint256 withdrawnCollateral = Math.min(
            strategyBank.getWithdrawableCollateral(address(strategyAccount)),
            amount
        );

        if (withdrawnCollateral > 0) {
            _expectEmitWithdrawCollateral(
                address(strategyBank),
                address(strategyAccount),
                address(this),
                withdrawnCollateral
            );
        }
        strategyAccount.executeWithdrawCollateral(
            address(this),
            amount,
            isSoftWithdraw
        );

        if (SKIP_VALIDATIONS) {
            return;
        }

        // Verify correct change in holdings.
        oldHoldings.collateral -= withdrawnCollateral;
        _validateHoldings(id, oldHoldings);

        // Verify balances.
        _validateAssetTransfer(
            address(strategyBank),
            address(this),
            oldStrategyBankBalance,
            oldSenderBalance,
            withdrawnCollateral
        );
    }

    // Protocol Utilities.

    function _expectRevert(string memory revertMsg) internal {
        vm.expectRevert(bytes(revertMsg));
    }

    // Protocol Cheats.

    function _simulateProfitOrLoss(
        IStrategyAccount sa,
        uint256 assetChange,
        bool isProfit
    ) internal {
        StrategyAccountMock asMock = StrategyAccountMock(address(sa));

        if (isProfit) {
            usdc.mint(address(sa), assetChange);
            asMock.experienceProfit(assetChange);
            return;
        }

        asMock.experienceLoss(assetChange);
    }

    // Events.

    /// Strategy Bank.

    function _expectEmitRepayLoan(
        address strategyBankAddress,
        address strategyAccount,
        uint256 loanRepaid,
        uint256 assetChange,
        bool isProfit
    ) internal {
        vm.expectEmit(true, true, true, true, strategyBankAddress);
        emit RepayLoan(
            strategyAccount,
            loanRepaid,
            (isProfit) ? 0 : assetChange
        );
    }

    // Utilities.

    function _refreshState(uint256 index) internal {
        strategyReserves[index].deposit(0, msg.sender);
    }

    // ============ Private Functions ============

    // Utilities.

    function _getLiquidationImpactOnStrategyBankBalance(
        int256 signedInsuranceDelta,
        IStrategyBank strategyBank,
        uint256 oldInsurance,
        uint256 oldStrategyBankBalance,
        uint256 collateral,
        uint256 oldCollateral
    ) private {
        uint256 insurancePremium = 0;
        uint256 insuranceDeficit = 0;
        if (signedInsuranceDelta > 0) {
            insurancePremium = uint256(signedInsuranceDelta);
        } else {
            insuranceDeficit = uint256(signedInsuranceDelta * -1);
        }

        uint256 newInsurance = oldInsurance +
            insurancePremium -
            insuranceDeficit;
        assertEq(
            TestUtilities.getInsuranceFund(strategyBank, usdc),
            newInsurance,
            "Insurance fund != expected."
        );

        assertEq(
            usdc.balanceOf(address(strategyBank)),
            oldStrategyBankBalance +
                insurancePremium -
                (oldCollateral - collateral) -
                insuranceDeficit,
            "Strategy bank != expected."
        );
    }

    // Event Checks.

    /// Strategy Reserve

    function _expectEmitDeposit(
        uint256 index,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) private {
        vm.expectEmit(true, true, true, true, address(strategyReserves[index]));
        emit Deposit(caller, receiver, assets, shares);
    }

    function _expectEmitWithdraw(
        uint256 index,
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) private {
        vm.expectEmit(true, true, true, true, address(strategyReserves[index]));
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _expectEmitBorrowAssets(
        address reserve,
        uint256 borrowAmount
    ) private {
        vm.expectEmit(true, true, true, true, reserve);
        emit BorrowAssets(borrowAmount);
    }

    function _expectEmitRepay(
        address reserve,
        uint256 initialLoan,
        uint256 returnedLoan
    ) private {
        vm.expectEmit(true, true, true, true, reserve);
        emit Repay(initialLoan, returnedLoan);
    }

    /// Strategy Bank

    function _expectEmitLiquidateLoan(
        address strategyBankAddress,
        address liquidator,
        address strategyAccount,
        uint256 loanLoss,
        uint256 premium
    ) private {
        vm.expectEmit(true, true, true, true, strategyBankAddress);
        emit LiquidateLoan(liquidator, strategyAccount, loanLoss, premium);
    }

    function _expectEmitBorrowFunds(
        address strategyBankAddress,
        address strategyAccount,
        uint256 loan
    ) private {
        vm.expectEmit(true, true, true, true, strategyBankAddress);
        emit BorrowFunds(strategyAccount, loan);
    }

    function _expectEmitAddCollateral(
        address strategyBankAddress,
        address sender,
        address strategyAccount,
        uint256 collateral
    ) private {
        vm.expectEmit(true, true, true, true, strategyBankAddress);
        emit AddCollateral(sender, strategyAccount, collateral);
    }

    function _expectEmitWithdrawCollateral(
        address strategyBankAddress,
        address strategyAccount,
        address onBehalfOf,
        uint256 collateral
    ) private {
        vm.expectEmit(true, true, true, true, strategyBankAddress);
        emit WithdrawCollateral(strategyAccount, onBehalfOf, collateral);
    }

    // Getters.

    function _getStrategyAccountHoldings(
        uint256 id
    ) private view returns (IStrategyBank.StrategyAccountHoldings memory) {
        return
            strategyAccounts[id].STRATEGY_BANK().getStrategyAccountHoldings(
                address(strategyAccounts[id])
            );
    }

    // Validations.

    /// Strategy Bank.

    function _validateHoldings(
        uint256 id,
        IStrategyBank.StrategyAccountHoldings memory expectedHoldings
    ) private {
        IStrategyBank.StrategyAccountHoldings
            memory newHoldings = _getStrategyAccountHoldings(id);
        assertEq(
            newHoldings.collateral,
            expectedHoldings.collateral,
            "Collateral != expected."
        );
        assertEq(newHoldings.loan, expectedHoldings.loan, "Loan != expected.");
        assertEq(
            newHoldings.interestIndexLast,
            expectedHoldings.interestIndexLast,
            "Interest index last != expected."
        );
    }

    /// General.

    function _validateAssetTransfer(
        address sender,
        address receiver,
        uint256 oldSenderBalance,
        uint256 oldReceiverBalance,
        uint256 amount
    ) private {
        uint256 receiverBalance = usdc.balanceOf(receiver);
        uint256 senderBalance = usdc.balanceOf(sender);

        // Validate balances in each contract.
        assertEq(
            receiverBalance,
            oldReceiverBalance + amount,
            "Receiver balance != expected."
        );
        assertEq(
            senderBalance,
            oldSenderBalance - amount,
            "Sender balance != expected."
        );
    }
}

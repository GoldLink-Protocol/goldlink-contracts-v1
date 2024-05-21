// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import { TestUtilities } from "../testLibraries/TestUtilities.sol";
import { TestConstants } from "../testLibraries/TestConstants.sol";
import { Constants } from "../../contracts/libraries/Constants.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { TestConstants } from "../testLibraries/TestConstants.sol";
import { PercentMath } from "../../contracts/libraries/PercentMath.sol";
import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import { StrategyBank } from "../../contracts/core/StrategyBank.sol";
import { Errors } from "../../contracts/libraries/Errors.sol";
import { StrategyAccountMock } from "../mocks/StrategyAccountMock.sol";
import { StrategyReserve } from "../../contracts/core/StrategyReserve.sol";
import {
    IStrategyAccountDeployer
} from "../../contracts/interfaces/IStrategyAccountDeployer.sol";
import {
    IStrategyController
} from "../../contracts/interfaces/IStrategyController.sol";
import {
    IStrategyAccount
} from "../../contracts/interfaces/IStrategyAccount.sol";
import {
    IStrategyReserve
} from "../../contracts/interfaces/IStrategyReserve.sol";

import { StateManager } from "../StateManager.sol";

contract StrategyBankTest is StateManager {
    using Math for uint256;
    using Math for uint16;
    using PercentMath for uint256;

    // ============ Constants ============

    uint256 constant fiftyThousand = 50000;
    uint256 constant oneHundredThousand = 100000;

    // ============ Storage Variables ============

    IStrategyController strategyController;
    uint256 minimumOpenHealthScore;
    uint256 LIQUIDATABLE_HEALTH_SCORE;
    uint256 totalValueLockedCap;

    uint256 amount;

    IStrategyBank.BankParameters parameters;

    // ============ Events ============

    event UpdateMinimumOpenHealthScore(uint256 newMinimumOpenHealthScore);

    event GetInterestAndTakeInsurance(
        uint256 interestRequested,
        uint256 fromCollateral,
        uint256 interestAndInsurance
    );

    // ============ Constructor  ============

    constructor() StateManager(false) {}

    // ============ Setup ============

    function setUp() public {
        strategyController = strategyControllers[0];
        minimumOpenHealthScore = 0.5e18; // 50%
        LIQUIDATABLE_HEALTH_SCORE = 0.25e18; // 25%
        totalValueLockedCap = TestConstants.ONE_HUNDRED_USDC * 1e10;

        amount = 100;

        TestUtilities.mintAndApprove(
            usdc,
            TestConstants.ONE_HUNDRED_USDC,
            address(strategyReserves[0])
        );

        TestUtilities.mintAndApprove(
            usdc,
            TestConstants.ONE_HUNDRED_USDC,
            address(strategyReserves[1])
        );

        TestUtilities.mintAndApprove(
            usdc,
            TestConstants.ONE_HUNDRED_USDC,
            address(strategyBanks[0])
        );
        TestUtilities.mintAndApprove(
            usdc,
            TestConstants.ONE_HUNDRED_USDC,
            address(strategyBanks[2])
        );

        parameters = TestUtilities.defaultBankParameters(
            TestUtilities.defaultStrategyDeployer()
        );
    }

    // ============ Constructor Tests ============

    function testZeroStrategyAccountDeployerAddress() public {
        IStrategyBank.BankParameters memory bankParams = TestUtilities
            .defaultBankParameters(IStrategyAccountDeployer(address(this)));
        bankParams.strategyAccountDeployer = IStrategyAccountDeployer(
            address(0)
        );

        _expectRevert(Errors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        new StrategyBank(
            address(this),
            usdc,
            IStrategyController(address(this)),
            IStrategyReserve(address(this)),
            bankParams
        );
    }

    function testExecutorPremiumOneHundredPercent() public {
        IStrategyBank.BankParameters memory bankParams = TestUtilities
            .defaultBankParameters(IStrategyAccountDeployer(address(this)));
        bankParams.executorPremium = Constants.ONE_HUNDRED_PERCENT;

        _expectRevert(
            Errors
                .STRATEGY_BANK_EXECUTOR_PREMIUM_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT
        );
        new StrategyBank(
            address(this),
            usdc,
            IStrategyController(address(this)),
            IStrategyReserve(address(this)),
            bankParams
        );
    }
    function testZeroLiquidationHealthScore() public {
        IStrategyBank.BankParameters memory bankParams = TestUtilities
            .defaultBankParameters(IStrategyAccountDeployer(address(this)));
        bankParams.liquidatableHealthScore = 0;

        _expectRevert(
            Errors
                .STRATEGY_BANK_LIQUIDATABLE_HEALTH_SCORE_MUST_BE_GREATER_THAN_ZERO
        );
        new StrategyBank(
            address(this),
            usdc,
            IStrategyController(address(this)),
            IStrategyReserve(address(this)),
            bankParams
        );
    }

    function testInsurancePremiumOneHundredPercent() public {
        IStrategyBank.BankParameters memory bankParams = TestUtilities
            .defaultBankParameters(IStrategyAccountDeployer(address(this)));
        bankParams.insurancePremium = Constants.ONE_HUNDRED_PERCENT;

        _expectRevert(
            Errors
                .STRATEGY_BANK_INSURANCE_PREMIUM_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT
        );
        new StrategyBank(
            address(this),
            usdc,
            IStrategyController(address(this)),
            IStrategyReserve(address(this)),
            bankParams
        );
    }

    function testLiquidationInsurancePremiumOneHundredPercent() public {
        IStrategyBank.BankParameters memory bankParams = TestUtilities
            .defaultBankParameters(IStrategyAccountDeployer(address(this)));
        bankParams.liquidationInsurancePremium = Constants.ONE_HUNDRED_PERCENT;

        _expectRevert(
            Errors
                .STRATEGY_BANK_LIQUIDATION_INSURANCE_PREMIUM_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT
        );
        new StrategyBank(
            address(this),
            usdc,
            IStrategyController(address(this)),
            IStrategyReserve(address(this)),
            bankParams
        );
    }

    function testOneHundredPercentLiquidationHealthScore() public {
        IStrategyBank.BankParameters memory bankParams = TestUtilities
            .defaultBankParameters(IStrategyAccountDeployer(address(this)));
        bankParams.liquidatableHealthScore = Constants.ONE_HUNDRED_PERCENT;

        _expectRevert(
            Errors
                .STRATEGY_BANK_LIQUIDATABLE_HEALTH_SCORE_MUST_BE_LESS_THAN_ONE_HUNDRED_PERCENT
        );
        new StrategyBank(
            address(this),
            usdc,
            IStrategyController(address(this)),
            IStrategyReserve(address(this)),
            bankParams
        );
    }

    // ============ Update Minimum Open Health Score Tests ============

    function testUpdateMinimumOpenHealthScoreWithMinimumHealthBelowLiquidatable()
        public
    {
        _expectRevert(
            Errors
                .STRATEGY_BANK_MINIMUM_OPEN_HEALTH_SCORE_CANNOT_BE_AT_OR_BELOW_LIQUIDATABLE_HEALTH_SCORE
        );
        strategyBanks[0].updateMinimumOpenHealthScore(
            LIQUIDATABLE_HEALTH_SCORE - 1
        );
    }

    function testUpdateMinimumOpenHealthScore() public {
        assertEq(
            strategyBanks[0].minimumOpenHealthScore_(),
            minimumOpenHealthScore
        );

        uint256 newMinimumOpenHealthScore = 75e16;

        vm.expectEmit(true, true, true, true, address(strategyBanks[0]));
        emit UpdateMinimumOpenHealthScore(newMinimumOpenHealthScore);
        strategyBanks[0].updateMinimumOpenHealthScore(
            newMinimumOpenHealthScore
        );

        assertEq(
            strategyBanks[0].minimumOpenHealthScore_(),
            newMinimumOpenHealthScore
        );
    }

    // ============ Take Interest and Insurance Tests ============

    function testGetInterestAndTakeInsuranceNotStrategyReserve() public {
        _expectRevert(Errors.STRATEGY_BANK_CALLER_MUST_BE_STRATEGY_RESERVE);
        strategyBanks[0].getInterestAndTakeInsurance(100);
    }

    function testGetInterestAndTakeInsuranceNoBalanceToPay() public {
        _expectEmitGetInterestAndTakeInsurance(100, 0, 0);
        vm.prank(address(strategyBanks[0].STRATEGY_RESERVE()));
        assertEq(strategyBanks[0].getInterestAndTakeInsurance(100), 0);

        _verifyTotalCollateral(0);
    }

    function testGetInterestAndTakeInsuranceNotEnoughBalanceToPay() public {
        strategyAccounts[0].executeAddCollateral(50);

        _expectEmitGetInterestAndTakeInsurance(100, 50, 50);
        vm.prank(address(strategyBanks[0].STRATEGY_RESERVE()));
        assertEq(strategyBanks[0].getInterestAndTakeInsurance(100), 50);

        _verifyTotalCollateral(0);
    }

    function testGetInterestAndTakeInsuranceNotEnoughBalanceToCollectFullyInsurance()
        public
    {
        strategyAccounts[0].executeAddCollateral(98);

        _expectEmitGetInterestAndTakeInsurance(100, 98, 98);
        vm.prank(address(strategyBanks[0].STRATEGY_RESERVE()));
        assertEq(strategyBanks[0].getInterestAndTakeInsurance(100), 95);

        _verifyTotalCollateral(0);
    }

    function testGetInterestAndTakeInsurance() public {
        strategyAccounts[0].executeAddCollateral(105);

        _expectEmitGetInterestAndTakeInsurance(100, 100, 100);
        vm.prank(address(strategyBanks[0].STRATEGY_RESERVE()));
        assertEq(strategyBanks[0].getInterestAndTakeInsurance(100), 95);

        _verifyTotalCollateral(5);
    }

    function testGetInterestAndTakeInsurancePartlyWithInsurance() public {
        strategyAccounts[0].executeAddCollateral(50);

        // Insurance
        usdc.mint(address(strategyBanks[0]), 50);

        _expectEmitGetInterestAndTakeInsurance(100, 50, 100);
        vm.prank(address(strategyBanks[0].STRATEGY_RESERVE()));
        assertEq(strategyBanks[0].getInterestAndTakeInsurance(100), 95);

        _verifyTotalCollateral(0);
    }

    function testGetInterestAndTakeInsurancePartlyWithNewInsurance() public {
        strategyAccounts[0].executeAddCollateral(50);

        // Insurance
        usdc.mint(address(strategyBanks[0]), 48);

        _expectEmitGetInterestAndTakeInsurance(100, 50, 98);
        vm.prank(address(strategyBanks[0].STRATEGY_RESERVE()));
        assertEq(strategyBanks[0].getInterestAndTakeInsurance(100), 95);

        _verifyTotalCollateral(0);
    }

    function testFuzzGetInterestAndTakeInsurance(
        uint16 totalCollateral,
        uint16 insurance,
        uint16 interest
    ) public {
        vm.assume(totalCollateral >= TestConstants.MINIMUM_COLLATERAL_BALANCE);

        strategyAccounts[0].executeAddCollateral(totalCollateral);

        // Insurance
        usdc.mint(address(strategyBanks[0]), insurance);

        // End collateral is collateral less interest and insurance withholding.
        uint256 finalCollateral = totalCollateral -
            Math.min(totalCollateral, interest);

        uint256 withholding = 0;
        if (interest > 0) {
            withholding = uint256(interest).percentToFraction(
                TestConstants.DEFAULT_INSURANCE_PREMIUM
            );
        }

        uint256 finalInterest = Math.min(
            interest - withholding,
            uint256(totalCollateral) + insurance
        );

        uint256 finalSB = 0;
        if (uint256(totalCollateral) + insurance > interest - withholding) {
            finalSB =
                uint256(totalCollateral) +
                insurance -
                (interest - withholding);
        }

        // Run pay interest.
        _expectEmitGetInterestAndTakeInsurance(
            interest,
            Math.min(interest, uint256(totalCollateral)),
            Math.min(interest, uint256(totalCollateral) + insurance)
        );
        vm.prank(address(strategyBanks[0].STRATEGY_RESERVE()));
        assertEq(
            strategyBanks[0].getInterestAndTakeInsurance(interest),
            finalInterest
        );

        _verifyTotalCollateral(finalCollateral);
    }

    // ============ Execute Liquidate Tests ============

    function testProcessLiquidationWhenPaused() public {
        _createLender(0, 2000, 2000);

        _addCollateral(0, 500);
        _borrow(0, 1000);

        vm.warp(block.timestamp + 36500 days);
        strategyAccounts[0].executeInitiateLiquidation();

        strategyController.pause();
        _expectRevert(Errors.CANNOT_CALL_FUNCTION_WHEN_PAUSED);
        strategyAccounts[0].executeProcessLiquidation();
    }

    function testProcessLiquidationNoBorrower() public {
        _expectRevert(
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_INACTIVE
        );
        strategyAccounts[0].executeProcessLiquidation();
    }

    function testProcessLiquidationNoLoan() public {
        vm.prank(address(strategyAccounts[0]));
        (uint256 executorPremium, uint256 loanLoss) = strategyBanks[0]
            .processLiquidation(msg.sender, 0);
        assertEq(executorPremium, 0);
        assertEq(loanLoss, 0);
    }

    function testProcessLiquidationBorrowerForExcessInterest() public {
        _createLender(0, 2000, 2000);

        _addCollateral(0, 500);
        _borrow(0, 1000);

        vm.warp(block.timestamp + 36500 days);

        // 0 loss, 10k interest owed, 500 collateral, 0 insurance.
        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 1000,
                expectedLoanLoss: 0,
                expectedInterestPaid: 500,
                expectedPremium: 0,
                expectedCollateralRemaining: 0,
                expectedInsuranceDelta: 0,
                expectedInsuranceFromInterest: 0
            })
        );
    }

    function testProcessLiquidationBorrowerForExcessInterestAndHighInsurance()
        public
    {
        _createLender(0, 2000, 2000);

        _buildInsurance();

        _addCollateral(0, 40);
        _borrow(0, 80);

        vm.warp(block.timestamp + 7280 days);

        // 0 loss, 80 interest owed, 40 collateral, 500 insurance.
        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 80,
                expectedLoanLoss: 0,
                expectedPremium: 0,
                expectedInterestPaid: 83,
                expectedCollateralRemaining: 0,
                expectedInsuranceDelta: -43,
                expectedInsuranceFromInterest: 0
            })
        );
    }

    function testProcessLiquidationBorrower() public {
        _createLender(0, 2000, 2000);

        _addCollateral(0, 500);
        _borrow(0, 1000);

        _simulateProfitOrLoss(strategyAccounts[0], 300, false);

        vm.warp(block.timestamp + 365 days);

        // 300 loss, 100 interest owed, 500 collateral, 0 insurance.
        // Add 5 for interest insurance, 60 for premium and 23 for insurance.
        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 1000,
                expectedLoanLoss: 0,
                expectedPremium: 5,
                expectedInterestPaid: 100,
                expectedCollateralRemaining: 55,
                expectedInsuranceDelta: 45,
                expectedInsuranceFromInterest: 5
            })
        );
    }

    function testProcessLiquidationBorrowerJustLoss() public {
        _createLender(0, 2000, 2000);

        _addCollateral(0, 500);
        _borrow(0, 1000);

        _simulateProfitOrLoss(strategyAccounts[0], 300, false);

        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 1000,
                expectedLoanLoss: 0,
                expectedPremium: 5,
                expectedInterestPaid: 0,
                expectedCollateralRemaining: 155,
                expectedInsuranceDelta: 40,
                expectedInsuranceFromInterest: 0
            })
        );
    }

    function testProcessLiquidationBorrowerJustLossSmallInsurance() public {
        _createLender(0, 2000, 2000);

        _addCollateral(0, 500);
        _borrow(0, 1000);

        _simulateProfitOrLoss(strategyAccounts[0], 493, false);

        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 1000,
                expectedLoanLoss: 0,
                expectedPremium: 3,
                expectedInterestPaid: 0,
                expectedCollateralRemaining: 0,
                expectedInsuranceDelta: 4,
                expectedInsuranceFromInterest: 0
            })
        );
    }

    function testProcessLiquidationBorrowerJustLossNoInsurance() public {
        _createLender(0, 2000, 2000);

        _addCollateral(0, 500);
        _borrow(0, 1000);

        _simulateProfitOrLoss(strategyAccounts[0], 498, false);

        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 1000,
                expectedLoanLoss: 0,
                expectedPremium: 2,
                expectedInterestPaid: 0,
                expectedCollateralRemaining: 0,
                expectedInsuranceDelta: 0,
                expectedInsuranceFromInterest: 0
            })
        );
    }

    function testProcessLiquidationBorrowerWithProfit() public {
        _createLender(0, 2000, 2000);

        _addCollateral(0, 500);
        _borrow(0, 1000);

        vm.warp(block.timestamp + 36500 days);

        // Has no impact on liquidation.
        _simulateProfitOrLoss(strategyAccounts[0], 300, true);

        // -300 loss, 10k interest owed, 500 collateral, 0 insurance.
        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 1000,
                expectedLoanLoss: 0,
                expectedPremium: 0,
                expectedInterestPaid: 500,
                expectedCollateralRemaining: 0,
                expectedInsuranceDelta: 0,
                expectedInsuranceFromInterest: 0
            })
        );
    }

    function testProcessLiquidationBorrowerLoanLoss() public {
        _createLender(0, 2000, 2000);

        _addCollateral(0, 500);
        _borrow(0, 1000);

        _simulateProfitOrLoss(strategyAccounts[0], 600, false);

        vm.warp(block.timestamp + 365 days);

        // 600 loss, 100 interest owed, 500 collateral, 0 insurance.
        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 805,
                expectedLoanLoss: 195,
                expectedPremium: 0,
                expectedInterestPaid: 100,
                expectedCollateralRemaining: 0,
                expectedInsuranceDelta: 0,
                expectedInsuranceFromInterest: 5
            })
        );
    }

    function testProcessLiquidationLoanLossCoveredByInsurance() public {
        _createLender(0, 1000, 1000);

        _buildInsurance();

        _addCollateral(0, 50);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 60, false);

        // 500 insurance, 60 loss, 50 collateral.
        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 100,
                expectedLoanLoss: 0,
                expectedPremium: 0,
                expectedInterestPaid: 0,
                expectedCollateralRemaining: 0,
                expectedInsuranceDelta: -10,
                expectedInsuranceFromInterest: 0
            })
        );
    }

    function testProcessLiquidationLoanLossAndInterestCoveredByInsurance()
        public
    {
        _createLender(0, 1000, 1000);

        _buildInsurance();

        _addCollateral(0, 50);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 60, false);

        vm.warp(block.timestamp + 365 days);

        // 500 insurance, 6 interest, 60 loss, 50 collateral.
        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 100,
                expectedLoanLoss: 0,
                expectedPremium: 0,
                expectedInterestPaid: 6,
                expectedCollateralRemaining: 0,
                expectedInsuranceDelta: -16,
                expectedInsuranceFromInterest: 0
            })
        );
    }

    function testProcessLiquidationBorrowerForLossAndExcessInteresPartiallyCovered()
        public
    {
        _createLender(0, 2000, 2000);

        _buildInsurance();

        _addCollateral(0, 400);
        _borrow(0, 800);

        vm.warp(block.timestamp + 7280 days);

        _simulateProfitOrLoss(strategyAccounts[0], 200, false);

        _liquidate(
            0,
            0,
            ExpectedLiquidationValues({
                expectedRepayAmount: 600,
                expectedLoanLoss: 200,
                expectedPremium: 0,
                expectedInterestPaid: 900,
                expectedCollateralRemaining: 0,
                expectedInsuranceDelta: -500,
                expectedInsuranceFromInterest: 0
            })
        );
    }

    // ============ Add Collateral Tests ============

    function testAddCollateralWhenPaused() public {
        strategyController.pause();

        vm.prank(address(strategyAccounts[0]));
        _expectRevert(Errors.CANNOT_CALL_FUNCTION_WHEN_PAUSED);
        strategyBanks[0].addCollateral(address(this), 50);
    }

    function testAddCollateralNotStrategyAccount() public {
        vm.prank(address(1));
        _expectRevert(
            Errors.STRATEGY_BANK_CALLER_IS_NOT_VALID_STRATEGY_ACCOUNT
        );
        strategyBanks[0].addCollateral(address(this), 50);
    }

    function testAddCollateralBelowMinimum() public {
        vm.prank(address(strategyAccounts[0]));
        _expectRevert(
            Errors.STRATEGY_BANK_COLLATERAL_WOULD_BE_LESS_THAN_MINIMUM
        );
        strategyBanks[0].addCollateral(
            address(this),
            TestConstants.MINIMUM_COLLATERAL_BALANCE - 1
        );
    }

    function testAddCollateralZeroAmount() public {
        _addCollateral(0, 0);
    }

    function testAddCollateralThenAddLessThanMinimumAfterInterestBringsBelow()
        public
    {
        _createLender(0, 4, 4);

        _addCollateral(0, 4);
        _borrow(0, 4);

        vm.warp(2000 days);

        vm.prank(address(strategyAccounts[0]));

        _expectRevert(
            Errors.STRATEGY_BANK_COLLATERAL_WOULD_BE_LESS_THAN_MINIMUM
        );
        strategyBanks[0].addCollateral(
            address(this),
            TestConstants.MINIMUM_COLLATERAL_BALANCE - 1
        );
    }

    function testAddCollateral() public {
        _addCollateral(0, 50);
    }

    function testAddCollateralThenAddLessThanMinimum() public {
        _addCollateral(0, 50);
        _addCollateral(0, TestConstants.MINIMUM_COLLATERAL_BALANCE - 1);
    }

    function testFuzzAddCollateral(uint256 collateral) public {
        vm.assume(collateral >= TestConstants.MINIMUM_COLLATERAL_BALANCE);
        vm.assume(collateral <= type(uint224).max);

        _addCollateral(0, collateral);
    }

    // ============ Borrow Funds Tests ============

    function testBorrowFundsWhenPaused() public {
        strategyController.pause();
        _expectRevert(Errors.CANNOT_CALL_FUNCTION_WHEN_PAUSED);
        strategyAccounts[0].executeBorrow(amount * 2);
    }

    function testBorrowFundsOverBorrow() public {
        // First user enrolls 100 in s1 and 50 in s2.
        _createLender(0, amount, amount);

        _addCollateral(0, amount * 2);

        vm.expectRevert();
        strategyAccounts[0].executeBorrow(amount * 2);
    }

    function testBorrowFundsNoBalance() public {
        _borrow(0, 0);
    }

    function testBorrowFundsHealthScoreNotRespected() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);

        _expectRevert(
            Errors
                .STRATEGY_BANK_HEALTH_SCORE_WOULD_FALL_BELOW_MINIMUM_OPEN_HEALTH_SCORE
        );
        strategyAccounts[0].executeBorrow(300);
    }

    function testBorrowFundsNoLoan() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 0);
    }

    function testBorrowFundsPartial2x() public {
        _createLender(0, 100, 100);

        _createLender(2, 100, 100);

        for (uint256 i = 0; i < 2; i++) {
            _addCollateral(0, 25);
            _borrow(0, 25);
        }
    }

    function testBorrowFundsFull() public {
        _createLender(0, 100, 100);

        _createLender(1, 100, 100);

        _addCollateral(1, 50);
        _borrow(1, 50);
    }

    function testBorrowFundsMultiple() public {
        // First user enrolls 100 in s1 and 50 in s2.
        _createLender(0, 100, 100);

        // Second user enrolls 100 in s1 and 50 in s3.
        _createLender(2, 100, 100);

        // 50 funds utilized in s1, 12.5 in s2 and 12.5 in s3.
        // 10 funds utilized in s3, 0 in s2 and 10 in s1.
        _addCollateral(0, 50);
        _borrow(0, 50);

        _addCollateral(2, 10);
        _borrow(2, 10);
    }

    function testBorrowFundsAfterLoss() public {
        _createLender(0, 30000, 30000);

        uint256 collateral = 13744;
        uint256 loan = 6872;
        _addCollateral(0, collateral);
        _borrow(0, loan);

        uint256 loss = 4871;
        _simulateProfitOrLoss(strategyAccounts[0], loss, false);

        uint256 adjustedCollateral = collateral - loss;
        uint256 maxLoan = adjustedCollateral.mulDiv(
            1e18,
            strategyBanks[0].minimumOpenHealthScore_()
        ) - loan;

        _borrow(0, maxLoan);
    }

    function testBorrowFundsWithProfit() public {
        // First user enrolls 100 in s1 and 50 in s2.
        _createLender(0, 100, 100);

        // Second user enrolls 100 in s1 and 50 in s3.
        _createLender(2, 100, 100);

        // 50 funds utilized in s1, 12.5 in s2 and 12.5 in s3.
        // 10 funds utilized in s3, 0 in s2 and 10 in s1.
        _addCollateral(0, 50);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 1000, true);

        _addCollateral(0, 10);

        _expectRevert(
            Errors
                .STRATEGY_BANK_HEALTH_SCORE_WOULD_FALL_BELOW_MINIMUM_OPEN_HEALTH_SCORE
        );
        strategyAccounts[0].executeBorrow(100);
    }

    function testFuzzBorrowFunds(uint256 fuzzAmount) public {
        _createLender(0, 100, 100);

        _createLender(2, 100, 100);

        vm.assume(fuzzAmount <= 100);
        vm.assume(fuzzAmount >= TestConstants.MINIMUM_COLLATERAL_BALANCE);

        _addCollateral(0, fuzzAmount);
        _borrow(0, fuzzAmount);
    }

    // ============ Repay Loan Tests ============

    function testRepayLoanRepayAmountMoreThanBorrowed() public {
        vm.prank(address(strategyAccounts[0]));

        _expectRevert(Errors.STRATEGY_BANK_CANNOT_REPAY_MORE_THAN_TOTAL_LOAN);
        strategyBanks[0].repayLoan(1000, 50000);
    }

    function testRepayLoanBeyondOneHundredPercent() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        _expectRevert(Errors.STRATEGY_BANK_CANNOT_REPAY_MORE_THAN_TOTAL_LOAN);
        strategyAccounts[0].executeRepayLoan(100);
    }

    function testRepayLoanLossLiquidatable() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 30, false);

        _expectRevert(Errors.STRATEGY_BANK_CANNOT_REPAY_LOAN_WHEN_LIQUIDATABLE);
        strategyAccounts[0].executeRepayLoan(50);
    }

    function testRepayLoanWhenFundsAreDeployed() public {
        _createLender(0, oneHundredThousand, oneHundredThousand);

        _addCollateral(0, fiftyThousand);
        _borrow(0, fiftyThousand);

        strategyAccounts[0].deployFunds(fiftyThousand);

        _expectRevert(
            Errors.STRATEGY_BANK_CANNOT_REPAY_MORE_THAN_IS_IN_STRATEGY_ACCOUNT
        );
        strategyAccounts[0].executeRepayLoan(fiftyThousand);
    }

    function testRepayLoanFailsHealthCheckAfterInterest() public {
        _createLender(0, oneHundredThousand, oneHundredThousand);

        _addCollateral(0, fiftyThousand);
        _borrow(0, fiftyThousand);

        vm.warp(block.timestamp + 365 days);

        _borrow(0, 1);

        vm.warp(block.timestamp + 36500 days);

        _expectRevert(Errors.STRATEGY_BANK_CANNOT_REPAY_LOAN_WHEN_LIQUIDATABLE);
        strategyAccounts[0].executeRepayLoan(fiftyThousand);
    }

    function testRepayLoanZeroAmount() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        _repayLoan(0, ExpectedRepayLoanValues(0, 0, false, 0, 0, 0, 0, false));
    }

    function testRepayLoanNoProfitOrLoss() public {
        _createLender(0, oneHundredThousand, oneHundredThousand);

        _addCollateral(0, fiftyThousand);
        _borrow(0, fiftyThousand);

        vm.warp(block.timestamp + 365 days);

        _borrow(0, 1);

        vm.warp(block.timestamp + 365 days);

        _borrow(0, 1);

        // 9886 of interest.

        uint256 thisBalance = usdc.balanceOf(address(this));

        // Pause the strategy.
        // It should still be possible to repay the loan while paused.
        strategyController.pause();

        _expectEmitRepayLoan(
            address(strategyBanks[0]),
            address(strategyAccounts[0]),
            50002,
            0,
            false
        );
        _repayLoanToSelfAndVerify(50002, 0, false);

        _checkRepayFull(strategyReserves[0], 40607, thisBalance, 109393);
        // Check that second address == expected.
        assertEq(
            usdc.balanceOf(address(TestConstants.SECOND_ADDRESS)),
            0,
            "Second address != expected."
        );
        _verifyStrategyAccountHoldings(fiftyThousand - 9887, 0);
    }

    // function testRepayLoanNoProfitOrLossPartial() public {
    //     _createLender(0, 100, 100);

    //     _addCollateral(0, 50);
    //     _borrow(0, 50);

    //     _repayLoan(0, ExpectedRepayLoanValues(25, 0, false, 0, 0, 1e18, 1e18, false));
    // }

    function testRepayLoanProfit() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        _simulateProfitOrLoss(strategyAccounts[0], 100, true);

        _repayLoan(
            0,
            ExpectedRepayLoanValues(50, 100, true, 0, 0, 0, 0, false)
        );
    }

    function testRepayLoanProfitFullyOffsettingInterest() public {
        _createLender(0, oneHundredThousand, oneHundredThousand);

        _addCollateral(0, fiftyThousand);
        _borrow(0, fiftyThousand);

        vm.warp(block.timestamp + 365 days);

        _borrow(0, 1);

        vm.warp(block.timestamp + 365 days);

        _borrow(0, 1);

        // 9886 of interest.

        _simulateProfitOrLoss(strategyAccounts[0], 11000, true);

        uint256 thisBalance = usdc.balanceOf(address(this));

        _expectEmitRepayLoan(
            address(strategyBanks[0]),
            address(strategyAccounts[0]),
            50002,
            11000,
            true
        );
        _repayLoanToSelfAndVerify(50002, 11000, true);

        _checkRepayFull(strategyReserves[0], 40607, thisBalance, 109393);
        _verifyStrategyAccountHoldings(fiftyThousand - 9887, 0);
    }

    function testRepayLoanProfitAndLiquidatableInterest() public {
        _createLender(0, oneHundredThousand, oneHundredThousand);

        _addCollateral(0, fiftyThousand);
        _borrow(0, fiftyThousand);

        vm.warp(block.timestamp + 36500 days);

        _simulateProfitOrLoss(strategyAccounts[0], 6000000, true);

        _expectRevert(Errors.STRATEGY_BANK_CANNOT_REPAY_LOAN_WHEN_LIQUIDATABLE);
        strategyAccounts[0].executeRepayLoan(fiftyThousand);
    }

    function testRepayLoanProfit2x() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        _simulateProfitOrLoss(strategyAccounts[0], 100, true);

        _repayLoan(0, ExpectedRepayLoanValues(25, 50, true, 0, 0, 0, 0, false));
        _repayLoan(0, ExpectedRepayLoanValues(25, 75, true, 0, 0, 0, 0, false));
    }

    function testRepayLoanProfitLessThanOffsettingInterest() public {
        _createLender(0, oneHundredThousand, oneHundredThousand);

        _addCollateral(0, fiftyThousand);
        _borrow(0, fiftyThousand);

        vm.warp(block.timestamp + 365 days);

        _borrow(0, 1);

        vm.warp(block.timestamp + 365 days);

        _borrow(0, 1);

        // 9886 of interest.

        _simulateProfitOrLoss(strategyAccounts[0], 9000, true);

        assertEq(
            strategyBanks[0]
                .getStrategyAccountHoldings(address(strategyAccounts[0]))
                .collateral,
            40113
        );

        // interest already paid
        _repayLoan(
            0,
            ExpectedRepayLoanValues(
                50002,
                9000,
                true,
                0,
                0,
                197733651551312649,
                197733651551312649,
                true
            )
        );
    }

    function testRepayLoanLossAndInterest() public {
        _createLender(0, oneHundredThousand, oneHundredThousand);

        _addCollateral(0, fiftyThousand);
        _borrow(0, fiftyThousand);

        vm.warp(block.timestamp + 365 days);

        _borrow(0, 1);

        vm.warp(block.timestamp + 365 days);

        _borrow(0, 1);

        _simulateProfitOrLoss(strategyAccounts[0], 4000, false);

        assertEq(
            strategyBanks[0]
                .getStrategyAccountHoldings(address(strategyAccounts[0]))
                .collateral,
            40113
        );

        _repayLoan(
            0,
            ExpectedRepayLoanValues(
                50002,
                4000,
                false,
                0,
                0,
                197733651551312649,
                197733651551312649,
                true
            )
        );
    }

    function testRepayLoanLoss() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        _simulateProfitOrLoss(strategyAccounts[0], 10, false);

        _repayLoan(
            0,
            ExpectedRepayLoanValues(50, 10, false, 0, 0, 0, 0, false)
        );
    }

    function testFuzzRepayLoanProfit(
        uint256 borrowAmount,
        uint256 profit
    ) public {
        vm.assume(borrowAmount > 0);
        _createLender(0, 100, 100);

        _createLender(2, 100, 100);

        vm.assume(borrowAmount <= 100);
        vm.assume(borrowAmount >= TestConstants.MINIMUM_COLLATERAL_BALANCE);

        _addCollateral(0, borrowAmount);
        _borrow(0, borrowAmount);

        if (borrowAmount == 0) {
            return;
        }

        profit = Math.min(profit, borrowAmount);
        if (profit > 0) {
            _simulateProfitOrLoss(strategyAccounts[0], profit, true);
        }

        _expectEmitRepayLoan(
            address(strategyBanks[0]),
            address(strategyAccounts[0]),
            borrowAmount,
            profit,
            profit > 0
        );
        _repayLoanToSelfAndVerify(borrowAmount, profit, profit > 0);

        _verifyStrategyAccountHoldings(borrowAmount, 0);
    }

    // ============ Withdraw Collateral Tests ============

    function testWithdrawCollateralWhenPaused() public {
        strategyController.pause();

        vm.prank(address(strategyAccounts[0]));
        _expectRevert(Errors.CANNOT_CALL_FUNCTION_WHEN_PAUSED);
        strategyBanks[0].withdrawCollateral(address(this), 50, false);
    }

    function testWithdrawCollateralMoreThanAccountHas() public {
        vm.prank(address(strategyAccounts[0]));

        _expectRevert(
            Errors.STRATEGY_BANK_CANNOT_DECREASE_COLLATERAL_BELOW_ZERO
        );

        strategyBanks[0].withdrawCollateral(
            TestConstants.SECOND_ADDRESS,
            50,
            false
        );
    }

    function testWithdrawCollateralInvalidOnBehalfOf() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        vm.prank(address(strategyAccounts[0]));

        vm.expectRevert(TestConstants.ERC20_ZERO_ADDRESS_ERROR_BYTES);
        strategyBanks[0].withdrawCollateral(address(0), 10, false);
    }

    function testWithdrawCollateralBeyondCollateral() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        vm.prank(address(strategyAccounts[0]));

        _expectRevert(
            Errors.STRATEGY_BANK_CANNOT_DECREASE_COLLATERAL_BELOW_ZERO
        );
        strategyBanks[0].withdrawCollateral(address(this), 100, false);
    }

    function testWithdrawCollateralCannotWithdrawBeyondHoldings() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 80);

        vm.prank(address(strategyAccounts[0]));

        _expectRevert(
            Errors
                .STRATEGY_BANK_REQUESTED_WITHDRAWAL_AMOUNT_EXCEEDS_AVAILABLE_COLLATERAL
        );
        strategyBanks[0].withdrawCollateral(address(this), 50, false);
    }

    function testWithdrawCollateralMaintainBelowMinimumBalance() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);

        _withdrawCollateral(0, 48, false);

        vm.prank(address(strategyAccounts[0]));

        _expectRevert(
            Errors.STRATEGY_BANK_COLLATERAL_WOULD_BE_LESS_THAN_MINIMUM
        );
        strategyBanks[0].withdrawCollateral(address(this), 1, false);
    }

    function testWithdrawCollateralZeroCollateral() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        _withdrawCollateral(0, 0, false);
    }

    function testWithdrawCollateralWithdrawZero() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 25);
        _borrow(0, 50);

        _withdrawCollateral(0, 25, true);
    }

    function testWithdrawCollateral() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        _withdrawCollateral(0, 25, false);
    }

    function testWithdrawCollateralWithInterest() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        vm.warp(block.timestamp + 365 days);

        _withdrawCollateral(0, 20, false);
    }

    function testWithdrawCollateralReducedForInterestFactorDown() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        vm.warp(block.timestamp + 365 days);

        // Reduced due to interest.
        _withdrawCollateral(0, 45, true);
    }

    function testWithdrawCollateralWhenNoLoanIsPresent() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);

        _withdrawCollateral(0, 48, false);
        _withdrawCollateral(0, 2, false);
    }

    function testFuzzWithdrawCollateral(
        uint256 fuzzAmount,
        uint256 withdrawAmount
    ) public {
        _createLender(0, 100, 100);

        _createLender(2, 100, 100);

        vm.assume(fuzzAmount <= 100);
        vm.assume(fuzzAmount >= TestConstants.MINIMUM_COLLATERAL_BALANCE);

        withdrawAmount = TestUtilities.maxFuzzValue(
            withdrawAmount,
            (
                fuzzAmount.mulDiv(
                    minimumOpenHealthScore,
                    Constants.ONE_HUNDRED_PERCENT
                )
            ),
            false
        );

        if (
            fuzzAmount - withdrawAmount != 0 &&
            fuzzAmount - withdrawAmount <
            TestConstants.MINIMUM_COLLATERAL_BALANCE
        ) {
            fuzzAmount += TestConstants.MINIMUM_COLLATERAL_BALANCE;
        }

        _addCollateral(0, fuzzAmount);
        _borrow(0, fuzzAmount);

        _withdrawCollateral(0, withdrawAmount, false);
    }

    // ============ Execute Open Account Tests ============

    function testExecuteOpenAccount() public {
        address newAccount = strategyBanks[0].executeOpenAccount(address(this));
        IStrategyAccount(newAccount).executeAddCollateral(50);

        assertEq(
            strategyBanks[0].getStrategyAccountHoldings(newAccount).collateral,
            50
        );
    }

    // ============ Probe Account Liquidation Tests ============

    function testIsAccountLiquidatableNoAccount() public {
        assertEq(
            strategyBanks[0].isAccountLiquidatable(
                address(strategyAccounts[0]),
                0
            ),
            false
        );
    }

    function testIsAccountLiquidatableNotLiquidatable() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 25);
        _borrow(0, 50);

        assertEq(
            strategyBanks[0].isAccountLiquidatable(
                address(strategyAccounts[0]),
                50
            ),
            false
        );
    }

    function testIsAccountLiquidatableNotLiquidatableButSomeInterestAndLoss()
        public
    {
        _createLender(0, 100, 100);

        _addCollateral(0, 25);
        _borrow(0, 50);

        vm.warp(50 days);

        assertEq(
            strategyBanks[0].isAccountLiquidatable(
                address(strategyAccounts[0]),
                40
            ),
            false
        );
    }

    function testIsAccountLiquidatableLiquidatableSomeInterestAndLoss() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 25);
        _borrow(0, 50);

        vm.warp(250 days);

        assertEq(
            strategyBanks[0].isAccountLiquidatable(
                address(strategyAccounts[0]),
                40
            ),
            true
        );
    }

    function testIsAccountLiquidatableLiquidatableHighLoss() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 25);
        _borrow(0, 50);

        assertEq(
            strategyBanks[0].isAccountLiquidatable(
                address(strategyAccounts[0]),
                20
            ),
            true
        );
    }

    function testIsAccountLiquidatableLiquidatableSomeInterestAndALotOfLoss()
        public
    {
        _createLender(0, 100, 100);

        _addCollateral(0, 25);
        _borrow(0, 50);

        vm.warp(50 days);

        assertEq(
            strategyBanks[0].isAccountLiquidatable(
                address(strategyAccounts[0]),
                15
            ),
            true
        );
    }

    function testIsAccountLiquidatableLiquidatableHighInterest() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 25);
        _borrow(0, 50);

        vm.warp(1500 days);

        // Utilization: 50%
        // Interest rate: 10%
        // Liquidatable health score: 25%
        //
        // Interest accrued = 1500 days * (1 year / 365 days) * (10% / year)
        //                  = 41% of loan = 21 (rounded up)
        //
        // Health score = (25 - 21) / 50 = 8%
        vm.prank(address(strategyAccounts[0]));
        assertEq(
            strategyBanks[0].isAccountLiquidatable(
                address(strategyAccounts[0]),
                50
            ),
            true
        );
    }

    // ============ Get Borrower Holdings Tests ============

    function testGetNoStrategyAccountHoldings() public {
        _verifyStrategyAccountHoldings(0, 0);
    }

    // ============ Get Accounts Tests ============
    function testGetAccountsBasic() public {
        strategyBanks[0].executeOpenAccount(address(this));
        strategyBanks[0].executeOpenAccount(address(this));
        strategyBanks[0].executeOpenAccount(address(this));
        strategyBanks[0].executeOpenAccount(address(this));

        address[] memory accs = strategyBanks[0].getStrategyAccounts(0, 2);
        require(accs.length == 2);

        accs = strategyBanks[0].getStrategyAccounts(0, 0);
        require(accs.length == 5);
        require(accs[4] != address(0));
    }

    // ============ Get Withdrawable Collateral Tests ============

    function testGetWithdrawableCollateralNoHoldings() public {
        assertEq(
            strategyBanks[0].getWithdrawableCollateral(
                address(strategyAccounts[0])
            ),
            0
        );
    }

    function testGetWithdrawableCollateralNoProfitOrLoss() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        assertEq(
            strategyBanks[0].getWithdrawableCollateral(
                address(strategyAccounts[0])
            ),
            25
        );
    }

    function testGetWithdrawableCollateralLoss() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        _simulateProfitOrLoss(strategyAccounts[0], 10, false);

        assertEq(
            strategyBanks[0].getWithdrawableCollateral(
                address(strategyAccounts[0])
            ),
            15
        );
    }

    function testGetWithdrawableCollateralMassiveLoss() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 50);

        _simulateProfitOrLoss(strategyAccounts[0], 50, false);

        assertEq(
            strategyBanks[0].getWithdrawableCollateral(
                address(strategyAccounts[0])
            ),
            0
        );
    }

    function testGetWithdrawableCollateralProfit() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 50);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 100, true);

        assertEq(
            strategyBanks[0].getWithdrawableCollateral(
                address(strategyAccounts[0])
            ),
            0
        );
    }

    // ============ Utilities ============

    // Run and Verify helpers.

    function _repayLoanToSelfAndVerify(
        uint256 repayAmount,
        uint256 expectedAssetChange,
        bool expectedIsProfit
    ) internal {
        strategyAccounts[0].executeRepayLoan(repayAmount);

        if (expectedIsProfit) {
            assertEq(
                expectedAssetChange,
                strategyAccounts[0].getAccountValue(),
                "Profit != expected."
            );
        }
    }

    function _buildInsurance() internal {
        usdc.mint(address(strategyBanks[0]), 500);
    }

    // Checks.
    function _checkRepayFull(
        IStrategyReserve reserve,
        uint256 strategyBankBalance,
        uint256 thisBalance,
        uint256 reserveBalance
    ) private {
        assertEq(reserve.utilizedAssets_(), 0);
        assertEq(
            usdc.balanceOf(address(strategyBanks[0])),
            strategyBankBalance,
            "Strategy bank balance != expected."
        );

        assertEq(
            usdc.balanceOf(address(reserve)),
            reserveBalance,
            "Reserve balance != expected."
        );
        assertEq(
            usdc.balanceOf(address(this)),
            thisBalance,
            "This balance != expected."
        );
    }

    function _verifyStrategyAccountHoldings(
        uint256 collateral,
        uint256 loan
    ) private {
        IStrategyBank.StrategyAccountHoldings memory holdings = strategyBanks[0]
            .getStrategyAccountHoldings(address(strategyAccounts[0]));

        assertEq(holdings.collateral, collateral, "Collateral != expected.");
        assertEq(holdings.loan, loan, "Loan != expected.");
    }

    function _verifyTotalCollateral(uint256 totalCollateral) private {
        assertEq(
            strategyBanks[0].totalCollateral_(),
            totalCollateral,
            "Total collateral != expected."
        );
    }

    // Event tests

    function _expectEmitGetInterestAndTakeInsurance(
        uint256 totalRequested,
        uint256 fromCollateral,
        uint256 interestAndInsurance
    ) private {
        vm.expectEmit(true, true, true, true, address(strategyBanks[0]));
        emit GetInterestAndTakeInsurance(
            totalRequested,
            fromCollateral,
            interestAndInsurance
        );
    }
}

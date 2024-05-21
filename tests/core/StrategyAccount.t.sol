// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TestConstants } from "../testLibraries/TestConstants.sol";
import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import { TestUtilities } from "../testLibraries/TestUtilities.sol";
import { GoldLinkERC20Mock } from "../mocks/GoldLinkERC20Mock.sol";
import { Errors } from "../../contracts/libraries/Errors.sol";
import { Constants } from "../../contracts/libraries/Constants.sol";
import { StateManager } from "../StateManager.sol";

contract StrategyAccountTest is StateManager {
    // ============ Constructor  ============

    constructor() StateManager(false) {}

    // ============ Setup ============

    function setUp() public {
        TestUtilities.mintAndApprove(
            usdc,
            TestConstants.ONE_HUNDRED_USDC,
            address(strategyBanks[0])
        );
    }

    // ============ Execute Borrow Tests ============

    function testExecuteBorrowNotOwner() public {
        vm.prank(TestConstants.SECOND_ADDRESS);

        _expectRevert(Errors.STRATEGY_ACCOUNT_SENDER_IS_NOT_OWNER);
        strategyAccounts[0].executeBorrow(100);
    }

    function testExecuteBorrow() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);
        _borrow(0, 100);
    }

    // ============ Execute Repay Loan Tests ============

    function testExecuteRepayLoanNotOwner() public {
        vm.prank(TestConstants.SECOND_ADDRESS);

        _expectRevert(Errors.STRATEGY_ACCOUNT_SENDER_IS_NOT_OWNER);
        strategyAccounts[0].executeRepayLoan(100);
    }

    function testExecuteRepayLoan() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);
        _borrow(0, 100);
        _repayLoan(0, ExpectedRepayLoanValues(50, 0, false, 0, 0, 0, 0, false));
    }

    function testExecuteRepayLoanProfitPartial() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 100, true);

        _repayLoan(0, ExpectedRepayLoanValues(50, 50, true, 0, 0, 0, 0, false));
    }

    function testExecuteRepayLoanProfit() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 100, true);

        _repayLoan(
            0,
            ExpectedRepayLoanValues(100, 100, true, 0, 0, 0, 0, false)
        );
    }

    function testExecuteRepayLoanLoss() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 10, false);

        _repayLoan(0, ExpectedRepayLoanValues(50, 0, false, 0, 0, 0, 0, false));
    }

    function testExecuteRepayLoanLossUpToCollateral() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 10, false);

        _repayLoan(0, ExpectedRepayLoanValues(90, 0, false, 0, 0, 0, 0, false));
    }

    function testExecuteRepayLoanLossIntoCollateral() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 10, false);

        _repayLoan(0, ExpectedRepayLoanValues(95, 5, false, 0, 0, 0, 0, false));
    }

    function testExecuteRepayLoanLossFull() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);
        _borrow(0, 100);

        _simulateProfitOrLoss(strategyAccounts[0], 10, false);

        _repayLoan(
            0,
            ExpectedRepayLoanValues(100, 10, false, 0, 0, 0, 0, false)
        );
    }

    // ============ Execute Withdraw Collateral Tests ============

    function testExecuteWithdrawCollateralNotOwner() public {
        vm.prank(TestConstants.SECOND_ADDRESS);

        _expectRevert(Errors.STRATEGY_ACCOUNT_SENDER_IS_NOT_OWNER);
        strategyAccounts[0].executeWithdrawCollateral(address(this), 50, true);
    }

    function testExecuteWithdrawCollateralZeroAddress() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);
        _borrow(0, 100);
        strategyAccounts[0].executeRepayLoan(50);

        vm.expectRevert(TestConstants.ERC20_ZERO_ADDRESS_ERROR_BYTES);
        strategyAccounts[0].executeWithdrawCollateral(address(0), 50, true);
    }

    function testExecuteWithdrawCollateral() public {
        _createLender(0, 100, 100);

        _addCollateral(0, 100);
        _borrow(0, 100);

        _repayLoan(0, ExpectedRepayLoanValues(50, 0, false, 0, 0, 0, 0, false));
        _withdrawCollateral(0, 50, true);
    }

    // ============ Execute Add Collateral Tests ============

    function testExecuteAddCollateral() public {
        _addCollateral(0, 100);
    }

    // ============ Get Positional Value Tests ============

    function testGetAccountValueNoPosition() public {
        assertEq(strategyAccounts[0].getAccountValue(), 0);
    }

    function testGetAccountValueUnwound() public {
        strategyAccounts[0].experienceProfit(100);
        assertEq(strategyAccounts[0].getAccountValue(), 100);
    }
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import {
    StrategyBankHelpers
} from "../../contracts/libraries/StrategyBankHelpers.sol";
import { Constants } from "../../contracts/libraries/Constants.sol";

contract StrategyBankHelpersTest is Test {
    // ============ Storage Variables ============

    uint256 constant interest = 5;

    IStrategyBank.StrategyAccountHoldings holdings =
        IStrategyBank.StrategyAccountHoldings(50, 100, 0);

    // ============ Get Adjusted Collateral Tests ============

    function testGetAdjustedCollateralNoChange() public {
        uint256 adjustedCollateral = StrategyBankHelpers.getAdjustedCollateral(
            holdings,
            holdings.loan
        );
        assertEq(adjustedCollateral, holdings.collateral);
    }

    function testGetAdjustedCollateralProfit() public {
        uint256 adjustedCollateral = StrategyBankHelpers.getAdjustedCollateral(
            holdings,
            holdings.loan + 1
        );
        assertEq(adjustedCollateral, holdings.collateral);
    }

    function testGetAdjustedCollateralLoss() public {
        uint256 adjustedCollateral = StrategyBankHelpers.getAdjustedCollateral(
            holdings,
            holdings.loan - 1
        );
        assertEq(adjustedCollateral, holdings.collateral - 1);
    }

    function testGetAdjustedCollateralLoanLoss() public {
        uint256 adjustedCollateral = StrategyBankHelpers.getAdjustedCollateral(
            holdings,
            holdings.loan - (holdings.collateral + 1)
        );
        assertEq(adjustedCollateral, 0);
    }

    // ============ Get Health Score Tests ============

    function testGetHealthScoreNoLoan() public {
        holdings.loan = 0;

        uint256 healthScore = StrategyBankHelpers.getHealthScore(
            holdings,
            holdings.loan
        );
        assertEq(healthScore, Constants.ONE_HUNDRED_PERCENT);
    }

    function testGetHealthScoreNoChange() public {
        uint256 healthScore = StrategyBankHelpers.getHealthScore(
            holdings,
            holdings.loan
        );
        assertEq(healthScore, Constants.ONE_HUNDRED_PERCENT / 2);
    }

    function testGetHealthScoreProfit() public {
        uint256 healthScore = StrategyBankHelpers.getHealthScore(
            holdings,
            holdings.loan + 1
        );
        assertEq(healthScore, Constants.ONE_HUNDRED_PERCENT / 2);
    }

    function testGetHealthScoreLoss() public {
        uint256 healthScore = StrategyBankHelpers.getHealthScore(
            holdings,
            holdings.loan - 1
        );
        assertEq(healthScore, 49e16);
    }
}

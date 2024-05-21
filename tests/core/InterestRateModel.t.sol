// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Constants } from "../../contracts/libraries/Constants.sol";
import { InterestRateModelMock } from "../mocks/InterestRateModelMock.sol";
import {
    IInterestRateModel
} from "../../contracts/interfaces/IInterestRateModel.sol";
import { TestConstants } from "../testLibraries/TestConstants.sol";
import "forge-std/Test.sol";

contract InterestRateModelTest is Test {
    // ============ Storage Variables ============

    InterestRateModelMock model;

    // ============ Setup ============

    function setUp() public {
        model = new InterestRateModelMock(
            IInterestRateModel.InterestRateModelParameters(
                TestConstants.DEFAULT_OPTIMAL_UTILIZATION,
                TestConstants.DEFAULT_BASE_INTEREST_RATE,
                TestConstants.DEFAULT_RATE_SLOPE_1,
                TestConstants.DEFAULT_RATE_SLOPE_2
            )
        );

        // The very first interest calculation will always be with zero assets.
        model.accrueReserveInterest(0, 0);
    }

    // ============ Update Model Tests ============

    function testUpdateModelWithOptimalAboveOneHundred() public {
        vm.expectRevert(
            "StrategyReserve: Optimal utilization must be less than or equal to one hundred percent."
        );
        model.updateModel(
            IInterestRateModel.InterestRateModelParameters(
                Constants.ONE_HUNDRED_PERCENT + 1,
                TestConstants.DEFAULT_BASE_INTEREST_RATE,
                TestConstants.DEFAULT_RATE_SLOPE_1,
                TestConstants.DEFAULT_RATE_SLOPE_2
            )
        );
    }

    // ============ Accrue Reserve Interest Tests ============

    function testAccrueReserveInterestNoTime() public {
        assertEq(model.accrueReserveInterest(100, 100), 0);
    }

    function testAccrueReserveInterestZeroUtilization() public {
        vm.warp(365 days);

        assertEq(model.accrueReserveInterest(0, 100), 0);
    }

    function testAccrueReserveInterestLowUtilization() public {
        vm.warp(365 days);

        assertEq(model.accrueReserveInterest(25, 100), 2);

        // Second window.
        vm.warp(730 days);
        assertEq(model.accrueReserveInterest(25, 100), 2);
    }

    function testAccrueReserveInterestMediumUtilization() public {
        vm.warp(365 days);

        assertEq(model.accrueReserveInterest(50, 100), 5);
    }

    function testAccrueReserveInterestHighUtilization() public {
        vm.warp(365 days);

        assertEq(model.accrueReserveInterest(75, 100), 12);
        // Second call does nothing as no time has passed.
        assertEq(model.accrueReserveInterest(75, 100), 0);
    }

    function testAccrueReserveInterestFullUtilization() public {
        vm.warp(365 days);

        assertEq(model.accrueReserveInterest(100, 100), 20);
    }

    // ============ Get Next Cumulative Interest Index Tests ============

    function testGetNextCumulativeInterestIndexNoTime() public {
        assertEq(model.getNextCumulativeInterestIndex(100, 100), 0);
    }

    function testGetNextCumulativeInterestIndexZeroUtilization() public {
        vm.warp(365 days);

        assertEq(model.getNextCumulativeInterestIndex(0, 100), 0);
    }

    function testGetNextCumulativeInterestIndexLowUtilization() public {
        vm.warp(365 days);

        assertEq(
            model.getNextCumulativeInterestIndex(25, 100),
            74999997621765601
        );

        // Second window.
        vm.warp(730 days);
        assertEq(
            model.getNextCumulativeInterestIndex(25, 100),
            149999997621765601
        );
    }

    function testGetNextCumulativeInterestIndexMediumUtilization() public {
        vm.warp(365 days);

        assertEq(
            model.getNextCumulativeInterestIndex(50, 100),
            99999996829020801
        );
        // No change.
        assertEq(
            model.getNextCumulativeInterestIndex(50, 100),
            99999996829020801
        );
    }

    function testGetNextCumulativeInterestIndexHighUtilization() public {
        vm.warp(365 days);

        assertEq(
            model.getNextCumulativeInterestIndex(75, 100),
            149999995243531202
        );
    }

    function testGetNextCumulativeInterestIndexFullUtilization() public {
        vm.warp(365 days);

        assertEq(
            model.getNextCumulativeInterestIndex(100, 100),
            199999993658041603
        );
    }

    // ============ Calculate Interest Owed Tests ============

    function testCalculateInterestOwedIndicesEqual() public {
        assertEq(
            model.calculateInterestOwed(
                100,
                Constants.ONE_HUNDRED_PERCENT,
                Constants.ONE_HUNDRED_PERCENT
            ),
            0
        );
    }

    function testCalculateInterestOwed() public {
        assertEq(
            model.calculateInterestOwed(
                100,
                Constants.ONE_HUNDRED_PERCENT,
                Constants.ONE_HUNDRED_PERCENT + 1e17
            ),
            10
        );
    }
}

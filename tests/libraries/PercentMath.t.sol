// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { PercentMath } from "../../contracts/libraries/PercentMath.sol";
import { Constants } from "../../contracts/libraries/Constants.sol";

contract PercentMathTest is Test {
    // ============ Get Percent Value Tests ============

    function testGetPercentValue() public {
        uint256 percentValue = PercentMath.percentToFraction(
            100,
            (Constants.ONE_HUNDRED_PERCENT / 3)
        );
        assertEq(percentValue, 33);
    }

    // ============ Get Percent Value Ceil Tests ============

    function testGetPercentValueCeil() public {
        uint256 percentValue = PercentMath.percentToFractionCeil(
            100,
            (Constants.ONE_HUNDRED_PERCENT / 3)
        );
        assertEq(percentValue, 34);
    }

    // ============ Get Percentage Tests ============

    function testGetPercentage() public {
        uint256 percentage = PercentMath.fractionToPercent(33, 97);

        assertEq(percentage, 340206185567010309);
    }

    // ============ Get Percentage Ceil Tests ============

    function testfractionToPercentCeil() public {
        uint256 percentage = PercentMath.fractionToPercentCeil(33, 97);
        assertEq(percentage, 340206185567010310);
    }
}

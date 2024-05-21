// SPDX-License-Identifier: AGPL-3.0

import { Constants } from "./Constants.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

pragma solidity 0.8.20;

/**
 * @title PercentMath
 * @author GoldLink
 *
 * @dev Library for calculating percentages and fractions from percentages.
 * Meant to handle getting fractions in WAD and fraction values from percentages.
 */
library PercentMath {
    using Math for uint256;

    // ============ Internal Functions ============

    /**
     * @notice Implements percent to fraction, deriving a fraction from a percentage.
     * @dev The percentage was calculated with WAD precision.
     * @dev Rounds down.
     * @param whole          The total value.
     * @param percentage     The percent of the whole to derive from.
     * @return fractionValue The value of the fraction.
     */
    function percentToFraction(
        uint256 whole,
        uint256 percentage
    ) internal pure returns (uint256 fractionValue) {
        return whole.mulDiv(percentage, Constants.ONE_HUNDRED_PERCENT);
    }

    /**
     * @notice Implements percent to fraction ceil, deriving a fraction from
     * the ceiling of a percentage.
     * @dev The percentage was calculated with WAD precision.
     * @dev Rounds up.
     * @param whole          The total value.
     * @param percentage     The percent of the whole to derive from.
     * @return fractionValue The value of the fraction.
     */
    function percentToFractionCeil(
        uint256 whole,
        uint256 percentage
    ) internal pure returns (uint256 fractionValue) {
        return
            whole.mulDiv(
                percentage,
                Constants.ONE_HUNDRED_PERCENT,
                Math.Rounding.Ceil
            );
    }

    /**
     * @notice Implements fraction to percent, deriving the percent of the whole
     * that a fraction is.
     * @dev The percentage is calculated with WAD precision.
     * @dev Rounds down.
     * @param fraction    The fraction value.
     * @param whole       The whole value.
     * @return percentage The percent of the whole the `fraction` represents.
     */
    function fractionToPercent(
        uint256 fraction,
        uint256 whole
    ) internal pure returns (uint256 percentage) {
        return fraction.mulDiv(Constants.ONE_HUNDRED_PERCENT, whole);
    }

    /**
     * @notice Implements fraction to percent ceil, deriving the percent of the whole
     * that a fraction is.
     * @dev The percentage is calculated with WAD precision.
     * @dev Rounds up.
     * @param fraction    The fraction value.
     * @param whole       The whole value.
     * @return percentage The percent of the whole the `fraction` represents.
     */
    function fractionToPercentCeil(
        uint256 fraction,
        uint256 whole
    ) internal pure returns (uint256 percentage) {
        return
            fraction.mulDiv(
                Constants.ONE_HUNDRED_PERCENT,
                whole,
                Math.Rounding.Ceil
            );
    }
}

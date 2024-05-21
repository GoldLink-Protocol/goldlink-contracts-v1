// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Constants } from "../libraries/Constants.sol";
import { PercentMath } from "../libraries/PercentMath.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { Errors } from "../libraries/Errors.sol";

/**
 * @title InterestRateModel
 * @author GoldLink
 *
 * @dev Interest Rate Model is responsible for calculating and storing borrower's APR and accrued
 * interest. Utilizes a kinked rate slope model for calculating interest rates.
 */
abstract contract InterestRateModel is IInterestRateModel {
    using Math for uint256;
    using PercentMath for uint256;

    // ============ Storage Variables ============

    /// @notice The model, made up of all of the interest rate parameters.
    InterestRateModelParameters public model_;

    /// @dev The cumulative interest index for the interest rate model.
    uint256 private cumulativeInterestIndex_;

    /// @dev The timestamp of last update.
    uint256 private lastUpdateTimestamp_;

    // ============ Constructor ============

    constructor(InterestRateModelParameters memory model) {
        // Set the model for the interest rate.
        _updateModel(model);
    }

    // ============ Public Functions ============
    /**
     * @notice Implements cumulative interest index, returning the cumulative
     * interest index
     * @return currentCumulativeInterestIndex The current cumulative interest
     * index value.
     */
    function cumulativeInterestIndex()
        public
        view
        returns (uint256 currentCumulativeInterestIndex)
    {
        return cumulativeInterestIndex_;
    }

    // ============ Internal Functions ============

    /**
     * @notice Update the model for the interest rate.
     * @dev Emits the `ModelUpdated()` event.
     * @param model The new model for the interest rate.
     */
    function _updateModel(InterestRateModelParameters memory model) internal {
        require(
            model.optimalUtilization <= Constants.ONE_HUNDRED_PERCENT,
            Errors
                .STRATEGY_RESERVE_OPTIMAL_UTILIZATION_MUST_BE_LESS_THAN_OR_EQUAL_TO_ONE_HUNDRED_PERCENT
        );

        model_ = model;

        emit ModelUpdated(
            model.optimalUtilization,
            model.baseInterestRate,
            model.rateSlope1,
            model.rateSlope2
        );
    }

    /**
     * @notice Settle the value of the cumulative interest index by accuring
     *  interest that has accumulated over the time period since the index was
     *  last settled.
     * @dev Emits the `InterestSettled()` event.
     * @param used          The amount of assets being used.
     * @param total         The total amount of assets, from used and available amounts.
     * @return interestOwed The interest owed since last update.
     */
    function _accrueInterest(
        uint256 used,
        uint256 total
    ) internal returns (uint256 interestOwed) {
        // Get seconds elapsed since last update.
        uint256 secondsElapsed = block.timestamp - lastUpdateTimestamp_;

        // Exit early if no time passed.
        if (secondsElapsed == 0) {
            return 0;
        }

        uint256 cumulativeIndexNext = _getNextCumulativeInterestIndex(
            used,
            total
        );

        // Get interest owed for the used amount given the change in cumulative interest index.
        interestOwed = _calculateInterestOwed(
            used,
            cumulativeInterestIndex_,
            cumulativeIndexNext
        );

        // Store the update index and timestamp.
        cumulativeInterestIndex_ = cumulativeIndexNext;
        lastUpdateTimestamp_ = block.timestamp;

        emit InterestSettled(block.timestamp, cumulativeIndexNext);

        return interestOwed;
    }

    /**
     * @notice Calculate the next cumulative interest index without writing to the state.
     * @param used               The amount of assets being used.
     * @param total              The total amount of assets in the pool.
     * @return interestIndexNext The next interest index.
     */
    function _getNextCumulativeInterestIndex(
        uint256 used,
        uint256 total
    ) internal view returns (uint256 interestIndexNext) {
        // Get seconds elapsed since last update.
        uint256 secondsElapsed = block.timestamp - lastUpdateTimestamp_;

        // Return if not time passed or no assets were used.
        if (used == 0 || secondsElapsed == 0) {
            return cumulativeInterestIndex_;
        }

        // Get the interest rate as an APR, according to utilization.
        uint256 apr = _getInterestRate(used, total);

        // Get the accrued interest rate for the time period by applying
        // the APR as a simple (non-compounding) interest rate.
        uint256 accruedInterestRateForPeriod = apr.mulDiv(
            secondsElapsed,
            Constants.SECONDS_PER_YEAR,
            Math.Rounding.Floor
        );

        // Calculate the new index, representing cumulative accrued interest.
        return cumulativeInterestIndex_ + accruedInterestRateForPeriod;
    }

    /**
     * @notice Calculate the interest owed given the borrow amount, the last interest index and the current interest index.
     * @param borrowAmount      The individual amount borrowed. This is used as a basis for calculating the interest owed.
     * @param interestIndexLast The last interest index that was stored.
     * @param interestIndexNow  The current interest index.
     * @return interestOwed     The interest owed, calculated from the different of the two points on the interest curve.
     */
    function _calculateInterestOwed(
        uint256 borrowAmount,
        uint256 interestIndexLast,
        uint256 interestIndexNow
    ) internal pure returns (uint256 interestOwed) {
        // If the interest index is equal to the last interest index,
        // then the interest owed since the last update is zero.
        if (interestIndexLast == interestIndexNow) {
            return 0;
        }

        // Calculate the percentage change of the current index versus the last updated index.
        // Uses `(curveNow / curveBefore) - 100%` to derive the owed interest.
        uint256 indexDiff = interestIndexNow - interestIndexLast;

        // Calculate the interest owed by taking a percent of the borrow amount.
        return borrowAmount.percentToFractionCeil(indexDiff);
    }

    // ============ Private Functions ============

    /**
     * @notice Calculate interest rate according to the model, from used and available amounts.
     * @param used          The amount of assets being used.
     * @param total         The total amount of assets in the pool.
     * @return interestRate The calculated interest rate as a simple APR. Denominated in units of:
     * rate per 100% utilization, as WAD.
     */
    function _getInterestRate(
        uint256 used,
        uint256 total
    ) private view returns (uint256 interestRate) {
        // Read the model parameters from storage.
        InterestRateModelParameters memory model = model_;

        // Compute the percentage of available assets that are currently used.
        // Note that utilization is represented as a fraction of one WAD (representing 100%).
        uint256 utilization = used.fractionToPercent(total);

        // Split utilization into the parts above and below the optimal point.
        uint256 utilizationAboveOptimal = utilization > model.optimalUtilization
            ? utilization - model.optimalUtilization
            : 0;
        uint256 utilizationBelowOptimal = utilization - utilizationAboveOptimal;

        // Multiply each part by the corresponding slope parameter.
        uint256 rateBelowOptimal = utilizationBelowOptimal.mulDiv(
            model.rateSlope1,
            Constants.ONE_HUNDRED_PERCENT
        );
        uint256 rateAboveOptimal = utilizationAboveOptimal.mulDiv(
            model.rateSlope2,
            Constants.ONE_HUNDRED_PERCENT
        );

        // Return the sum rate from the different parts.
        return model.baseInterestRate + rateBelowOptimal + rateAboveOptimal;
    }
}

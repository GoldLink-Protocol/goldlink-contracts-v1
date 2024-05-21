// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

/**
 * @title IInterestRateModel
 * @author GoldLink
 *
 * @dev Interface for an interest rate model, responsible for maintaining the
 * cumulative interest index over time.
 */
interface IInterestRateModel {
    // ============ Structs ============

    /// @dev Parameters for an interest rate model.
    struct InterestRateModelParameters {
        // Optimal utilization as a fraction of one WAD (representing 100%).
        uint256 optimalUtilization;
        // Base (i.e. minimum) interest rate a the simple (non-compounded) APR,
        // denominated in WAD.
        uint256 baseInterestRate;
        // The slope at which the interest rate increases with utilization
        // below the optimal point. Denominated in units of:
        // rate per 100% utilization, as WAD.
        uint256 rateSlope1;
        // The slope at which the interest rate increases with utilization
        // after the optimal point. Denominated in units of:
        // rate per 100% utilization, as WAD.
        uint256 rateSlope2;
    }

    // ============ Events ============

    /// @notice Emitted when updating the interest rate model.
    /// @param optimalUtilization The optimal utilization after updating the model.
    /// @param baseInterestRate   The base interest rate after updating the model.
    /// @param rateSlope1         The rate slope one after updating the model.
    /// @param rateSlope2         The rate slope two after updating the model.
    event ModelUpdated(
        uint256 optimalUtilization,
        uint256 baseInterestRate,
        uint256 rateSlope1,
        uint256 rateSlope2
    );

    /// @notice Emitted when interest is settled, updating the cumulative
    ///  interest index and/or the associated timestamp.
    /// @param timestamp               The block timestamp of the index update.
    /// @param cumulativeInterestIndex The new cumulative interest index after updating.
    event InterestSettled(uint256 timestamp, uint256 cumulativeInterestIndex);
}

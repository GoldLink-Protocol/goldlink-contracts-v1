// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IStrategyBank } from "../interfaces/IStrategyBank.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Constants } from "./Constants.sol";
import { PercentMath } from "./PercentMath.sol";

/**
 * @title StrategyBankHelpers
 * @author GoldLink
 *
 * @dev Library for strategy bank helpers.
 */
library StrategyBankHelpers {
    using PercentMath for uint256;

    // ============ Internal Functions ============

    /**
     * @notice Implements get adjusted collateral, decreasing for loss and interest owed.
     * @param holdings            The holdings being evaluated.
     * @param loanValue           The value of the loan assets at present.
     * @return adjustedCollateral The value of the collateral after adjustments.
     */
    function getAdjustedCollateral(
        IStrategyBank.StrategyAccountHoldings memory holdings,
        uint256 loanValue
    ) internal pure returns (uint256 adjustedCollateral) {
        uint256 loss = holdings.loan - Math.min(holdings.loan, loanValue);

        // Adjust collateral for loss, either down for `assetChange` or to zero.
        return holdings.collateral - Math.min(holdings.collateral, loss);
    }

    /**
     * @notice Implements get health score, calculating the current health score
     * for a strategy account's holdings.
     * @param holdings     The strategy account holdings to get health score of.
     * @param loanValue    The value of the loan assets at present.
     * @return healthScore The health score of the provided holdings.
     */
    function getHealthScore(
        IStrategyBank.StrategyAccountHoldings memory holdings,
        uint256 loanValue
    ) internal pure returns (uint256 healthScore) {
        // Handle case where loan is 0 and health score is necessarily 1e18.
        if (holdings.loan == 0) {
            return Constants.ONE_HUNDRED_PERCENT;
        }

        // Get the adjusted collateral after profit, loss and interest.
        uint256 adjustedCollateral = getAdjustedCollateral(holdings, loanValue);

        // Return health score as a ratio of `(collateral - loss - interest)`
        // to loan. This is then multiplied by 1e18.
        return adjustedCollateral.fractionToPercentCeil(holdings.loan);
    }
}

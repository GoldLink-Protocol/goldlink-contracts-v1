// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { InterestRateModel } from "../../contracts/core/InterestRateModel.sol";
import {
    IInterestRateModel
} from "../../contracts/interfaces/IInterestRateModel.sol";

contract InterestRateModelMock is InterestRateModel {
    constructor(
        InterestRateModelParameters memory model
    ) InterestRateModel(model) {
        // Empty.
    }

    function updateModel(InterestRateModelParameters memory model) external {
        _updateModel(model);
    }

    function accrueReserveInterest(
        uint256 used,
        uint256 total
    ) external returns (uint256 interestOwed) {
        return _accrueInterest(used, total);
    }

    function getNextCumulativeInterestIndex(
        uint256 used,
        uint256 total
    ) external view returns (uint256 interestIndexNext) {
        return _getNextCumulativeInterestIndex(used, total);
    }

    function calculateInterestOwed(
        uint256 borrowAmount,
        uint256 interestIndexLast,
        uint256 interestIndexNow
    ) external pure returns (uint256 interestOwed) {
        return
            _calculateInterestOwed(
                borrowAmount,
                interestIndexLast,
                interestIndexNow
            );
    }
}

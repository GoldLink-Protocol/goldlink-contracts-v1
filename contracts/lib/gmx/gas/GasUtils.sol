// SPDX-License-Identifier: BUSL-1.1

// Slightly modified version of https://github.com/gmx-io/gmx-synthetics/blob/178290846694d65296a14b9f4b6ff9beae28a7f7/contracts/gas/GasUtils.sol
// Modified as follows:
// - Removed all logic except order gas limit functions.

pragma solidity ^0.8.0;

import {
    IGmxV2DataStore
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import { Keys } from "../keys/Keys.sol";

library GasUtils {
    // ============ Internal Functions ============

    // @dev the estimated gas limit for increase orders
    // @param dataStore DataStore
    // @param order the order to estimate the gas limit for
    function estimateExecuteIncreaseOrderGasLimit(
        IGmxV2DataStore dataStore,
        uint256 swapPathLength,
        uint256 callbackGasLimit
    ) internal view returns (uint256) {
        uint256 gasPerSwap = dataStore.getUint(Keys.singleSwapGasLimitKey());
        return
            dataStore.getUint(Keys.increaseOrderGasLimitKey()) +
            gasPerSwap *
            swapPathLength +
            callbackGasLimit;
    }

    // @dev the estimated gas limit for decrease orders
    // @param dataStore DataStore
    // @param order the order to estimate the gas limit for
    function estimateExecuteDecreaseOrderGasLimit(
        IGmxV2DataStore dataStore,
        uint256 swapPathLength,
        uint256 callbackGasLimit
    ) internal view returns (uint256) {
        uint256 gasPerSwap = dataStore.getUint(Keys.singleSwapGasLimitKey());
        uint256 swapCount = swapPathLength;

        return
            dataStore.getUint(Keys.decreaseOrderGasLimitKey()) +
            gasPerSwap *
            swapCount +
            callbackGasLimit;
    }

    // @dev the estimated gas limit for swap orders
    // @param dataStore DataStore
    // @param order the order to estimate the gas limit for
    function estimateExecuteSwapOrderGasLimit(
        IGmxV2DataStore dataStore,
        uint256 swapPathLength,
        uint256 callbackGasLimit
    ) internal view returns (uint256) {
        uint256 gasPerSwap = dataStore.getUint(Keys.singleSwapGasLimitKey());
        return
            dataStore.getUint(Keys.swapOrderGasLimitKey()) +
            gasPerSwap *
            swapPathLength +
            callbackGasLimit;
    }
}

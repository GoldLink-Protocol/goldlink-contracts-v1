// SPDX-License-Identifier: BUSL-1.1

// Adapted from https://github.com/gmx-io/gmx-synthetics/blob/178290846694d65296a14b9f4b6ff9beae28a7f7/contracts/callback/IOrderCallbackReceiver.sol
// Modified as follows:
// - Removed all logic except order callbacks
// - Replaced object types replaced with GoldLink types

pragma solidity ^0.8.0;

import { IGmxV2OrderTypes } from "./IGmxV2OrderTypes.sol";
import { IGmxV2EventUtilsTypes } from "./IGmxV2EventUtilsTypes.sol";

interface IGmxV2OrderCallbackReceiver {
    function afterOrderExecution(
        bytes32 key,
        IGmxV2OrderTypes.Props memory order,
        IGmxV2EventUtilsTypes.EventLogData memory eventData
    ) external;

    function afterOrderCancellation(
        bytes32 key,
        IGmxV2OrderTypes.Props memory order,
        IGmxV2EventUtilsTypes.EventLogData memory eventData
    ) external;

    function afterOrderFrozen(
        bytes32 key,
        IGmxV2OrderTypes.Props memory order,
        IGmxV2EventUtilsTypes.EventLogData memory eventData
    ) external;
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    GmxFrfStrategyAccount
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyAccount.sol";

import {
    IGmxFrfStrategyManager
} from "../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";
import { MockAccountLib } from "./libraries/MockAccountLib.sol";
import { IGmxV2OrderTypes } from "../../../contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";


contract MockAccountExtension is
    GmxFrfStrategyAccount
{
    constructor(IGmxFrfStrategyManager manager) GmxFrfStrategyAccount(manager) {}

    function openPosition(
        IGmxV2OrderTypes.CreateOrderParams memory order
    )
        external
        payable
        onlyOwner
    {
        MockAccountLib.sendOrder(MANAGER, order, msg.value);
    }
}

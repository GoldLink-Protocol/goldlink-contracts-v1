// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    GmxFrfStrategyAccount
} from "../../../../contracts/strategies/gmxFrf/GmxFrfStrategyAccount.sol";
import {
    IGmxFrfStrategyManager
} from "../../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";

contract MockAccountExtension is GmxFrfStrategyAccount {
    constructor(
        IGmxFrfStrategyManager manager
    ) GmxFrfStrategyAccount(manager) {}

    function exec(
        address target,
        bytes memory data
    ) external payable returns (bool, bytes memory) {
        if (msg.value == 0) {
            return target.call{ value: msg.value }(data);
        }
        return target.call(data);
    }
}

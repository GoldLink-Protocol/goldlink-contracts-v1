// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    GmxFrfStrategyAccount
} from "../../../../contracts/strategies/gmxFrf/GmxFrfStrategyAccount.sol";

import {
    IGmxFrfStrategyManager
} from "../../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";

contract MockAccountExtension is
    GmxFrfStrategyAccount
{
    constructor(IGmxFrfStrategyManager manager) GmxFrfStrategyAccount(manager) {}

    function exec(
        address target,
        bytes memory data
    )
        external
        onlyOwner
        returns (bool, bytes memory)
    {
        return target.call(
            data
        );
    }

    function execPayable(
        address payable target,
        bytes memory data
    ) external payable onlyOwner returns (bool, bytes memory) {
        return target.call{value: msg.value}(data);
    }
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;


import { MockAccountHelpers } from "./MockAccountHelpers.sol";

import { GmxFrfStrategyMetadata } from "../GmxFrfStrategyMetadata.sol";


// 0xa11b501c2dd83acd29f6727570f2502faaa617f2
contract MockAccountTests is MockAccountHelpers {


    function testMockBasic() public {
        (, bytes32 orderKey) = ACCOUNT.executeCreateIncreaseOrder{value: 2e15}(GmxFrfStrategyMetadata.GMX_V2_ETH_USDC, 1e9, 2e15);
        _executeGmxOrder(orderKey);
    }
}

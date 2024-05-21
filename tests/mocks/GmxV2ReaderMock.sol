// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    IGmxV2MarketTypes
} from "../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2MarketTypes.sol";
import {
    IGmxV2DataStore
} from "../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    GmxFrfStrategyMetadata
} from "../strategies/gmxFrf/GmxFrfStrategyMetadata.sol";

contract GmxV2ReaderMock {
    address public collision = address(0);
    address public collision2 = address(1);

    function getMarket(
        IGmxV2DataStore,
        address key
    ) external view returns (IGmxV2MarketTypes.Props memory) {
        // Set longToken to be the same for 2 specific "markets" only.
        address longToken = key;
        if (key == collision || key == collision2) {
            longToken = address(2);
        }

        return
            IGmxV2MarketTypes.Props({
                marketToken: msg.sender,
                indexToken: msg.sender,
                longToken: longToken,
                shortToken: address(GmxFrfStrategyMetadata.USDC)
            });
    }
}

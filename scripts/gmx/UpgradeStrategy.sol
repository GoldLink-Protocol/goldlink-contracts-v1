// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {
    UpgradeableBeacon
} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {
    GmxFrfStrategyAccount
} from "../../contracts/strategies/gmxFrf/GmxFrfStrategyAccount.sol";
import {
    IGmxFrfStrategyManager
} from "../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";

contract UpgradeStrategy is Script {
    string constant DEPLOYER_PRIVATE_KEY_ENV_KEY = "DEPLOYER_PRIVATE_KEY";
    string constant MANAGER_ADDRESS_ENV_KEY = "MANAGER_ADDRESS";
    string constant BEACON_ADDRESS_ENV_KEY = "BEACON_ADDRESS";

    function run() public {
        uint256 privateKey = vm.envUint(DEPLOYER_PRIVATE_KEY_ENV_KEY);

        vm.startBroadcast(privateKey);

        IGmxFrfStrategyManager manager = IGmxFrfStrategyManager(
            vm.envAddress(MANAGER_ADDRESS_ENV_KEY)
        );

        address updatedLogic = address(new GmxFrfStrategyAccount(manager));
        UpgradeableBeacon beacon = UpgradeableBeacon(
            vm.envAddress(BEACON_ADDRESS_ENV_KEY)
        );
        beacon.upgradeTo(updatedLogic);
        vm.stopBroadcast();
    }
}

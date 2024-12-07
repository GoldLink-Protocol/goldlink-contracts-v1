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

    function run() public {
        uint256 privateKey = vm.envUint(DEPLOYER_PRIVATE_KEY_ENV_KEY);

        vm.startBroadcast(privateKey);

        IGmxFrfStrategyManager manager = IGmxFrfStrategyManager(
            0x975B4a621D937605Eaeb117C00653CfBFbFb46CC
        );

        address updatedLogic = address(new GmxFrfStrategyAccount(manager));

        console.log(updatedLogic);
        // UpgradeableBeacon beacon = UpgradeableBeacon(
        //     0x98E27951E80ba7ab480c8e352e1d605AcF01B1Af
        // );
        // beacon.upgradeTo(updatedLogic);
        vm.stopBroadcast();
    }
}

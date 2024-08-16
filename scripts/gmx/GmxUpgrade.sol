// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    UpgradeableBeacon
} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {
    GmxFrfStrategyAccount
} from "../../contracts/strategies/gmxFrf/GmxFrfStrategyAccount.sol";
import {
    IGmxFrfStrategyManager
} from "../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";

import {
    IGmxV2ExchangeRouter
} from "../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2ExchangeRouter.sol";
import {
    IGmxV2Reader
} from "../../contracts/lib/gmx/interfaces/external/IGmxV2Reader.sol";

contract GmxUpgrade is Script {
    string constant DEPLOYER_PRIVATE_KEY_ENV_KEY = "DEPLOYER_PRIVATE_KEY";

    IGmxFrfStrategyManager manager =
        IGmxFrfStrategyManager(0x975B4a621D937605Eaeb117C00653CfBFbFb46CC);

    IGmxV2ExchangeRouter constant GMX_EXCHANGE_ROUTER_NEW_DEPLOYMENT_ADDRESS =
        IGmxV2ExchangeRouter(0x69C527fC77291722b52649E45c838e41be8Bf5d5);

    IGmxV2Reader constant GMX_NEW_READER_CONTRACT_ADDRESS =
        IGmxV2Reader(0x5Ca84c34a381434786738735265b9f3FD814b824);

    UpgradeableBeacon beacon =
        UpgradeableBeacon(0x98E27951E80ba7ab480c8e352e1d605AcF01B1Af);

    function run() public {
        uint256 pkey = vm.envUint(DEPLOYER_PRIVATE_KEY_ENV_KEY);
        vm.startBroadcast(pkey);
        // First must upgrade strategy implementation.
        address updatedLogic = address(new GmxFrfStrategyAccount(manager));
        beacon.upgradeTo(updatedLogic);

        // Now update manager config to reflect new contract addresses.
        manager.setExchangeRouter(GMX_EXCHANGE_ROUTER_NEW_DEPLOYMENT_ADDRESS);
        manager.setReader(GMX_NEW_READER_CONTRACT_ADDRESS);
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {
    UpgradeableBeacon
} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    IGmxFrfStrategyDeployer
} from "../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyDeployer.sol";
import {
    IGmxFrfStrategyManager
} from "../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";
import {
    GmxFrfStrategyAccount
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyAccount.sol";
import {
    GmxFrfStrategyDeployer
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyDeployer.sol";
import {
    GmxFrfStrategyManager
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyManager.sol";
import {
    IChainlinkAdapter
} from "../../../contracts/adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import {
    IChainlinkAggregatorV3
} from "../../../contracts/adapters/chainlink/interfaces/external/IChainlinkAggregatorV3.sol";

import {
    IMarketConfiguration
} from "../../../contracts/strategies/gmxFrf/interfaces/IMarketConfiguration.sol";
import { GmxFrfStrategyMetadata } from "./GmxFrfStrategyMetadata.sol";

abstract contract StrategyDeployerHelper is Test {
    uint256 public constant LIQUIDATION_ORDER_TIMEOUT_DEADLINE = 10 minutes;

    /**
     * @dev Deploy GMX strategy manager as an upgradeable contract.
     */
    function deployManager(
        IChainlinkAdapter.OracleConfiguration memory oc
    )
        public
        returns (IGmxFrfStrategyManager managerProxy, ProxyAdmin proxyAdmin)
    {
        // Deploy manager as upgradeable proxy.
        address managerLogic = address(
            new GmxFrfStrategyManager(
                GmxFrfStrategyMetadata.USDC,
                GmxFrfStrategyMetadata.WETH,
                address(this)
            )
        );
        bytes memory initializerData = abi.encodeWithSelector(
            GmxFrfStrategyManager.initialize.selector,
            GmxFrfStrategyMetadata.getDeployments(),
            _defaultSharedOrderParameters(),
            oc,
            LIQUIDATION_ORDER_TIMEOUT_DEADLINE
        );
        managerProxy = IGmxFrfStrategyManager(
            address(
                new TransparentUpgradeableProxy(
                    managerLogic,
                    address(this), // initialOwner for the proxy admin
                    initializerData
                )
            )
        );

        // Get proxy admin.
        // Based on Upgrades.sol from openzeppelin-foundry-upgrades.
        bytes32 adminSlot = vm.load(
            address(managerProxy),
            ERC1967Utils.ADMIN_SLOT
        );
        proxyAdmin = ProxyAdmin(address(uint160(uint256(adminSlot))));

        return (managerProxy, proxyAdmin);
    }

    /**
     * @dev Deploy GMX strategy account deployer.
     */
    function deployAccountDeployer(
        IGmxFrfStrategyManager manager
    ) public returns (IGmxFrfStrategyDeployer deployer, address accountBeacon) {
        // Deploy strategy account logic contract.
        address accountLogic = address(new GmxFrfStrategyAccount(manager));

        // Create upgradeable beacon pointing to that logic contract.
        accountBeacon = address(
            new UpgradeableBeacon(
                accountLogic,
                address(this) // initialOwner for the beacon
            )
        );

        // Deploy the account deployer.
        deployer = new GmxFrfStrategyDeployer(accountBeacon);

        return (deployer, accountBeacon);
    }

    function _defaultSharedOrderParameters()
        private
        view
        returns (IMarketConfiguration.SharedOrderParameters memory)
    {
        return
            IMarketConfiguration.SharedOrderParameters(
                1e6,
                1e17,
                bytes32("GOLDLINK"),
                address(this),
                1.1e18
            );
    }
}

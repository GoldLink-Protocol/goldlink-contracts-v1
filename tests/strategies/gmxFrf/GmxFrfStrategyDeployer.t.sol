// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    GmxFrfStrategyManager
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyManager.sol";
import {
    IGmxFrfStrategyDeployer
} from "../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyDeployer.sol";
import {
    IGmxFrfStrategyManager
} from "../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";
import {
    IChainlinkAdapter
} from "../../../contracts/adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import {
    IStrategyController
} from "../../../contracts/interfaces/IStrategyController.sol";
import { StateManager } from "../../StateManager.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import { StrategyDeployerHelper } from "./StrategyDeployerHelper.sol";
import { GmxFrfStrategyMetadata } from "./GmxFrfStrategyMetadata.sol";

contract GmxFrfStrategyDeployerTest is StrategyDeployerHelper, StateManager {
    IGmxFrfStrategyDeployer accountDeployer;

    function setUp() public {
        IChainlinkAdapter.OracleConfiguration memory oc = IChainlinkAdapter
            .OracleConfiguration(1e6, GmxFrfStrategyMetadata.USDC_USD_ORACLE);
        (IGmxFrfStrategyManager manager, ) = deployManager(oc);
        (accountDeployer, ) = deployAccountDeployer(manager);
    }

    // ==================== Constructor ====================

    constructor() StateManager(false) {}

    // ==================== Deploy Account Tests ====================

    function testDeployAccountZeroOwner() public {
        _expectRevert(GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        accountDeployer.deployAccount(
            address(0),
            IStrategyController(address(0))
        );
    }
}

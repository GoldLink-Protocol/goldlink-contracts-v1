// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    StrategyController
} from "../../contracts/core/StrategyController.sol";
import { Errors } from "../../contracts/libraries/Errors.sol";

import { StateManager } from "../StateManager.sol";

contract StrategyControllerTest is StateManager {
    // ============ Storage Variables ============

    StrategyController controller;

    // ============ Setup ============

    function setUp() public {
        controller = StrategyController(address(strategyControllers[0]));
    }

    // ============ Constructor ============

    constructor() StateManager(false) {}

    // ============ Pause Tests ============

    function testPause() public {
        assert(!controller.isPaused());

        controller.pause();
        assert(controller.isPaused());

        controller.unpause();
        assert(!controller.isPaused());
    }

    // ============ Acquire Lock Tests ============

    function testAcquireLock() public {
        vm.startPrank(address(strategyBanks[0]));

        controller.acquireStrategyLock();

        _expectRevert(Errors.STRATEGY_CONTROLLER_LOCK_ALREADY_ACQUIRED);
        controller.acquireStrategyLock();

        controller.releaseStrategyLock();

        _expectRevert(Errors.STRATEGY_CONTROLLER_LOCK_NOT_ACQUIRED);
        controller.releaseStrategyLock();

        vm.stopPrank();
    }
}

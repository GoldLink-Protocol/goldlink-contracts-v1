// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Errors } from "../libraries/Errors.sol";
import { IStrategyController } from "../interfaces/IStrategyController.sol";
import { IStrategyBank } from "../interfaces/IStrategyBank.sol";
import { IStrategyReserve } from "../interfaces/IStrategyReserve.sol";

/**
 * @title ControllerHelpers
 * @author GoldLink
 *
 * @dev Abstract contract that contains logic for strategy contracts to access their controller.
 */
abstract contract ControllerHelpers {
    // ============ Constants ============

    /// @notice The `StrategyController` that manages this strategy.
    IStrategyController public immutable STRATEGY_CONTROLLER;

    // ============ Modifiers ============

    /// @dev Lock the strategy from reentrancy via the controller.
    modifier strategyNonReentrant() {
        STRATEGY_CONTROLLER.acquireStrategyLock();
        _;
        STRATEGY_CONTROLLER.releaseStrategyLock();
    }

    /// @dev Require the strategy to be unpaused.
    modifier whenNotPaused() {
        require(
            !STRATEGY_CONTROLLER.isPaused(),
            Errors.CANNOT_CALL_FUNCTION_WHEN_PAUSED
        );
        _;
    }

    // ============ Constructor ============

    constructor(IStrategyController controller) {
        require(
            address(controller) != address(0),
            Errors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );

        STRATEGY_CONTROLLER = controller;
    }

    // ============ Public Functions ============

    function isStrategyPaused() public view returns (bool isPaused) {
        return STRATEGY_CONTROLLER.isPaused();
    }
}

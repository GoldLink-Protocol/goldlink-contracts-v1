// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    OrderValidation
} from "../../../../contracts/strategies/gmxFrf/libraries/OrderValidation.sol";
import {
    GmxFrfStrategyErrors
} from "../../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import "forge-std/Test.sol";

import { StateManager } from "../../../StateManager.sol";

contract OrderValidationTest is StateManager {
    // ============ Constructor  ============

    constructor() StateManager(false) {}

    // ============ Setup ============

    function setUp() public {
        // Empty.
    }

    // ============ Validate Orders Enabled Tests ============

    function testValidateOrdersEnabledNotEnabled() public {
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_VALIDATION_ORDER_TYPE_IS_DISABLED
        );
        OrderValidation.validateOrdersEnabled(false);
    }

    function testValidateOrdersEnabled() public pure {
        OrderValidation.validateOrdersEnabled(true);
    }
}

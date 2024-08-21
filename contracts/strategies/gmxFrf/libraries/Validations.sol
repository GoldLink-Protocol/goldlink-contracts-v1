// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { GmxFrfStrategyErrors } from "../GmxFrfStrategyErrors.sol";
import {
    IGmxFrfStrategyManager
} from "../interfaces/IGmxFrfStrategyManager.sol";
import { Role } from "../../../lib/gmx/role/Role.sol";

/**
 * @title Validations
 * @author GoldLink
 *
 * @dev Validations required in the GmxFrfStrategyAccount.
 */
library Validations {
    function verifyCallerIsController(
        IGmxFrfStrategyManager manager
    ) external view {
        require(
            manager.gmxV2RoleStore().hasRole(msg.sender, Role.CONTROLLER),
            GmxFrfStrategyErrors
                .GMX_FRF_STRATEGY_ORDER_CALLBACK_RECEIVER_CALLER_MUST_HAVE_CONTROLLER_ROLE
        );
    }

    function verifyCanPayFee(uint256 fee, uint256 msgValue) external pure {
        require(
            fee <= msgValue,
            GmxFrfStrategyErrors.MSG_VALUE_LESS_THAN_PROVIDED_EXECUTION_FEE
        );
    }

    function verifyApprovedMarket(
        IGmxFrfStrategyManager manager,
        address market
    ) external view {
        require(
            manager.isApprovedMarket(market),
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
    }

    function verifyNonZeroAddress(address addressToCheck) external pure {
        require(
            addressToCheck != address(0),
            GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );
    }
}

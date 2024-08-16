// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { GmxFrfStrategyErrors } from "../GmxFrfStrategyErrors.sol";

/**
 * @title MulticallChecks
 * @author GoldLink
 *
 * @dev Checks multicall result and reverts if a failure occurs.
 */
library MulticallChecks {
    function verifyResult(bool success, bytes memory result) public pure {
        if (!success) {
            // Next 5 lines from https://ethereum.stackexchange.com/a/83577
            if (result.length < 68) revert();
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }
    }

    function verifyBalance(uint256 minBalance) external view {
        uint256 currentBalance = address(this).balance;
        require(
            currentBalance >= minBalance,
            GmxFrfStrategyErrors
                .TOO_MUCH_NATIVE_TOKEN_SPENT_IN_MULTICALL_EXECUTION
        );
    }

    function verifyNotInMultiCall(uint256 multicallStatus) external pure {
        // Check that this is not a nested multicall.
        require(
            multicallStatus == 1,
            GmxFrfStrategyErrors.NESTED_MULTICALLS_ARE_NOT_ALLOWED
        );
    }
}

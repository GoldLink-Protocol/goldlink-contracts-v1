// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

/**
 * @title LiquidationLogic
 * @author GoldLink
 *
 * @dev Logic for handling the liquidations for the GmxFrf strategy.
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
}

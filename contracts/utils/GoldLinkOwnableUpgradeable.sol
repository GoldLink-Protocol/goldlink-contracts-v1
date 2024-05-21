// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import { Errors } from "../libraries/Errors.sol";

/**
 * @title GoldLinkOwnableUpgradeable
 * @author GoldLink
 *
 * @dev Ownable contract that requires new owner to accept, and disallows renouncing ownership.
 */
abstract contract GoldLinkOwnableUpgradeable is Ownable2StepUpgradeable {
    // ============ Public Functions ============

    function renounceOwnership() public view override onlyOwner {
        revert(Errors.CANNOT_RENOUNCE_OWNERSHIP);
    }
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { Errors } from "../libraries/Errors.sol";

/**
 * @title GoldLinkOwnable
 * @author GoldLink
 *
 * @dev Ownable contract that requires new owner to accept, and disallows renouncing ownership.
 */
abstract contract GoldLinkOwnable is Ownable2Step {
    // ============ Public Functions ============

    function renounceOwnership() public view override onlyOwner {
        revert(Errors.CANNOT_RENOUNCE_OWNERSHIP);
    }
}

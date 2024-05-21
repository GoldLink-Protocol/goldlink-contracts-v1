// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IStrategyController } from "./IStrategyController.sol";

/**
 * @title IStrategyAccountDeployer
 * @author GoldLink
 *
 * @dev Interface for deploying strategy accounts.
 */
interface IStrategyAccountDeployer {
    // ============ External Functions ============

    /// @dev Deploy a new strategy account for the `owner`.
    function deployAccount(
        address owner,
        IStrategyController strategyController
    ) external returns (address);
}

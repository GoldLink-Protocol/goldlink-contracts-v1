// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    IStrategyAccountDeployer
} from "../../../interfaces/IStrategyAccountDeployer.sol";
import { IMarketConfiguration } from "./IMarketConfiguration.sol";
import { IDeploymentConfiguration } from "./IDeploymentConfiguration.sol";

/**
 * @title IGmxFrfStrategyDeployer
 * @author GoldLink
 *
 * @dev Strategy account deployer for the GMX FRF strategy.
 */
interface IGmxFrfStrategyDeployer is IStrategyAccountDeployer {
    // ============ External Functions ============

    /// @dev Get the address of the account beacon.
    function ACCOUNT_BEACON() external view returns (address beacon);
}

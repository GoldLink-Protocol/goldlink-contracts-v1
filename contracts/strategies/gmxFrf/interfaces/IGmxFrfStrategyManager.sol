// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IMarketConfiguration } from "./IMarketConfiguration.sol";
import { IDeploymentConfiguration } from "./IDeploymentConfiguration.sol";
import {
    IChainlinkAdapter
} from "../../../adapters/chainlink/interfaces/IChainlinkAdapter.sol";

/**
 * @title IGmxFrfStrategyManager
 * @author GoldLink
 *
 * @dev Interface for manager contract for configuration vars.
 */
interface IGmxFrfStrategyManager is
    IMarketConfiguration,
    IDeploymentConfiguration,
    IChainlinkAdapter
{}

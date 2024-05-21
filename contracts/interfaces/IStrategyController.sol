// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStrategyAccountDeployer } from "./IStrategyAccountDeployer.sol";
import { IStrategyBank } from "./IStrategyBank.sol";
import { IStrategyReserve } from "./IStrategyReserve.sol";

/**
 * @title IStrategyController
 * @author GoldLink
 *
 * @dev Interface for the `StrategyController`, which manages strategy-wide pausing, reentrancy and acts as a registry for the core strategy contracts.
 */
interface IStrategyController {
    // ============ External Functions ============

    /// @dev Aquire a strategy wide lock, preventing reentrancy across the entire strategy. Callers must unlock after.
    function acquireStrategyLock() external;

    /// @dev Release a strategy lock.
    function releaseStrategyLock() external;

    /// @dev Pauses the strategy, preventing it from taking any new actions. Only callable by the owner.
    function pause() external;

    /// @dev Unpauses the strategy. Only callable by the owner.
    function unpause() external;

    /// @dev Get the address of the `StrategyAccountDeployer` associated with this strategy.
    function STRATEGY_ACCOUNT_DEPLOYER()
        external
        view
        returns (IStrategyAccountDeployer deployer);

    /// @dev Get the address of the `StrategyAsset` associated with this strategy.
    function STRATEGY_ASSET() external view returns (IERC20 asset);

    /// @dev Get the address of the `StrategyBank` associated with this strategy.
    function STRATEGY_BANK() external view returns (IStrategyBank bank);

    /// @dev Get the address of the `StrategyReserve` associated with this strategy.
    function STRATEGY_RESERVE()
        external
        view
        returns (IStrategyReserve reserve);

    /// @dev Return if paused.
    function isPaused() external view returns (bool currentlyPaused);
}

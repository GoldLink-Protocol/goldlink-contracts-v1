// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GoldLinkOwnable } from "../utils/GoldLinkOwnable.sol";
import { Errors } from "../libraries/Errors.sol";
import { IStrategyBank } from "../interfaces/IStrategyBank.sol";
import {
    IStrategyAccountDeployer
} from "../interfaces/IStrategyAccountDeployer.sol";
import { IStrategyController } from "../interfaces/IStrategyController.sol";
import { IStrategyReserve } from "../interfaces/IStrategyReserve.sol";
import { StrategyReserve } from "../core/StrategyReserve.sol";

/**
 * @title StrategyController
 * @author GoldLink
 *
 * @notice Contract that manages essential strategy-wide functions, including global strategy reentrancy and pausing.
 */
contract StrategyController is GoldLinkOwnable, Pausable, IStrategyController {
    // ============ Constants ============

    /// @notice The `IERC20` asset associated with lending and borrowing in the strategy.
    IERC20 public immutable STRATEGY_ASSET;

    /// @notice The `StrategyBank` associated with this strategy.
    IStrategyBank public immutable STRATEGY_BANK;

    /// @notice The `StrategyReserve` associated with this strategy.
    IStrategyReserve public immutable STRATEGY_RESERVE;

    /// @notice The `StrategyAccountDeployer` associated with this strategy.
    IStrategyAccountDeployer public immutable STRATEGY_ACCOUNT_DEPLOYER;

    /// @dev The lock states.
    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    // Taken from: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/3def8f9d15871160a146353b975ad7adf4c2bf67/contracts/utils/ReentrancyGuard.sol
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    // ============ Storage Variables ============

    /// @dev Whether the status of the strategy is locked from reentrancy.
    uint256 private reentrancyStatus_;

    // ============ Modifiers ============

    /// @dev Modifier to allow only the strategy core contracts to call the function.
    modifier onlyStrategyCore() {
        require(
            msg.sender == address(STRATEGY_BANK) ||
                msg.sender == address(STRATEGY_RESERVE),
            Errors.STRATEGY_CONTROLLER_CALLER_IS_NOT_STRATEGY_CORE
        );
        _;
    }

    // ============ Constructor ============

    constructor(
        address strategyOwner,
        IERC20 strategyAsset,
        IStrategyReserve.ReserveParameters memory reserveParameters,
        IStrategyBank.BankParameters memory bankParameters
    ) Ownable(strategyOwner) {
        STRATEGY_ASSET = strategyAsset;

        // Create the strategy reserve. The reserve will create the bank.
        STRATEGY_RESERVE = new StrategyReserve(
            strategyOwner,
            strategyAsset,
            this,
            reserveParameters,
            bankParameters
        );
        STRATEGY_BANK = STRATEGY_RESERVE.STRATEGY_BANK();

        STRATEGY_ACCOUNT_DEPLOYER = bankParameters.strategyAccountDeployer;

        // Set initial reentrancy status to not entered.
        reentrancyStatus_ = NOT_ENTERED;
    }

    // ============ External Functions ============

    /**
     * @notice Pause the strategy, preventing it's contracts from taking any new actions.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the strategy.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Acquire a strategy wide lock, preventing reentrancy across the entire strategy.
     * @dev IMPORTANT: The acquire and release functions are intended to be used as part of a
     * modifier to guarantee that the release function is always called at the end of a transaction
     * in which acquire has been called. This ensures that the value of `reentrancyStatus_` must be
     * `NOT_ENTERED` in between transactions.
     */
    function acquireStrategyLock() external override onlyStrategyCore {
        require(
            reentrancyStatus_ == NOT_ENTERED,
            Errors.STRATEGY_CONTROLLER_LOCK_ALREADY_ACQUIRED
        );
        reentrancyStatus_ = ENTERED;
    }

    /**
     * @notice Release a strategy lock.
     * @dev IMPORTANT: The acquire and release functions are intended to be used as part of a
     * modifier to guarantee that the release function is always called at the end of a transaction
     * in which acquire has been called. This ensures that the value of `reentrancyStatus_` must be
     * `NOT_ENTERED` in between transactions.
     */
    function releaseStrategyLock() external override onlyStrategyCore {
        require(
            reentrancyStatus_ == ENTERED,
            Errors.STRATEGY_CONTROLLER_LOCK_NOT_ACQUIRED
        );
        reentrancyStatus_ = NOT_ENTERED;
    }

    /**
     * @notice Return whether or not the strategy is paused.
     */
    function isPaused() external view override returns (bool) {
        return paused();
    }
}

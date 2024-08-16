// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    IGmxFrfStrategyManager
} from "../interfaces/IGmxFrfStrategyManager.sol";
import { OrderLogic } from "../libraries/OrderLogic.sol";
import { Validations } from "../libraries/Validations.sol";

/**
 * @title GmxStrategyStorage
 * @author GoldLink
 *
 * @dev Storage contract for the GMX funding rate farming strategy.
 */
abstract contract GmxStrategyStorage {
    // ============ Constants ============

    /// @notice The manager contract that controls the strategy and maintains configuration state.
    IGmxFrfStrategyManager public immutable MANAGER;

    // ============ Storage Variables ============

    /// @notice Mapping that keep strack of who should recieve the execution fee refund given an order id. The mapping is cleared after the order is executed.
    mapping(bytes32 => address) public orderIdToExecutionFeeRefundRecipient_;

    /// @notice Temporary state variable that is set in the callback reciever to notify the recieve() function the address that the execution fee refund should be sent to.
    /// Cleared after the recieve() function is called. In the event the refund is 0, the recieve() function will not be activated, resulting in this state variable remaining set.
    /// This is not a problem, it will just be overwritten the next time a refund is needed, and no native tokens should be sent to the contract other than for paying execution fees.
    bytes32 public processingOrderId_;

    /// @notice Mapping that keeps track of pending liquidations.
    mapping(bytes32 => OrderLogic.PendingLiquidation)
        public pendingLiquidations_;

    /// @notice Last liquidation timestamp, used to determine how collateral claims are paid out in the event an account is eligible.
    uint256 public lastLiquidationTimestamp_;

    /// @notice Should be set when a multicall is active to prevent nested multicalls.
    /// The value `1` implies the contract is not current executing a multicall.
    /// The value `2` implies that the contract is currently executing a multicall.
    uint256 internal isInMulticall_;

    /**
     * @dev This is empty reserved space intended to allow future versions of this upgradeable
     *  contract to define new variables without shifting down storage in the inheritance chain.
     *  See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;

    // ============ Constructor ============

    constructor(IGmxFrfStrategyManager manager) {
        _onlyNonZeroAddress(address(manager));
        MANAGER = manager;
    }

    function _onlyNonZeroAddress(address addressToCheck) internal pure {
        Validations.verifyNonZeroAddress(addressToCheck);
    }
}

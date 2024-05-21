// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    BeaconProxy
} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {
    IGmxFrfStrategyDeployer
} from "./interfaces/IGmxFrfStrategyDeployer.sol";
import { IStrategyAccount } from "../../interfaces/IStrategyAccount.sol";
import { IStrategyController } from "../../interfaces/IStrategyController.sol";
import { GmxFrfStrategyErrors } from "./GmxFrfStrategyErrors.sol";

/**
 * @title GmxFrfStrategyDeployer
 * @author GoldLink
 *
 * @notice Contract that deploys new strategy accounts for the GMX funding rate farming strategy.
 */
contract GmxFrfStrategyDeployer is IGmxFrfStrategyDeployer {
    // ============ Constants ============

    /// @notice The upgradeable beacon specifying the implementation code for strategy accounts
    /// managed by this strategy manager.
    address public immutable ACCOUNT_BEACON;

    // ============ Modifiers ============

    /// @dev Require address is not zero.
    modifier onlyNonZeroAddress(address addressToCheck) {
        require(
            addressToCheck != address(0),
            GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );
        _;
    }

    // ============ Initializer ============

    constructor(address accountBeacon) onlyNonZeroAddress(accountBeacon) {
        ACCOUNT_BEACON = accountBeacon;
    }

    // ============ External Functions ============

    /**
     * @notice Deploy account, a new strategy account able to deploy funds into the GMX
     * delta neutral funding rate farming strategy. Since the deployed account does not have any special permissions throughout the protocol,
     * there is no reason to restrict verify the caller.
     * @param owner    The owner of the newly deployed account.
     * @return account The newly deployed account.
     */
    function deployAccount(
        address owner,
        IStrategyController strategyController
    )
        external
        override
        onlyNonZeroAddress(owner)
        onlyNonZeroAddress(address(strategyController))
        returns (address account)
    {
        bytes memory initializeCalldata = abi.encodeCall(
            IStrategyAccount.initialize,
            (owner, strategyController)
        );
        account = address(new BeaconProxy(ACCOUNT_BEACON, initializeCalldata));
    }
}

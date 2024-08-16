// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    MockAccountExtension
} from "./MockDeployment/MockAccountExtension.sol";
import {
    StrategyController
} from "../../../contracts/core/StrategyController.sol";
import { MockAccountHelpers } from "./MockDeployment/MockAccountHelpers.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import {
    IGmxV2OrderTypes
} from "@contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import {
    IGmxV2EventUtilsTypes
} from "@contracts/lib/gmx/interfaces/external/IGmxV2EventUtilsTypes.sol";
import { Errors } from "@contracts/libraries/Errors.sol";

contract GmxFrfMiscTests is MockAccountHelpers {
    // ============ Initialize ============

    function testInitializeOwnerIsZero() public {
        _expectRevert(GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        DEPLOYER.deployAccount(address(0), CONTROLLER);
    }

    function testInitializeStrategyControllerIsZero() public {
        _expectRevert(GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        DEPLOYER.deployAccount(address(this), StrategyController(address(0)));
    }

    function testInitializeAlreadyInitialized() public {
        address account = DEPLOYER.deployAccount(address(this), CONTROLLER);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        MockAccountExtension(payable(account)).initialize(
            address(this),
            CONTROLLER
        );
    }

    // ============ Receive ============

    function testReceiveNoPendingOrders() public {
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_MANAGEMENT_INVALID_FEE_REFUND_RECIPIENT
        );
        payable(address(ACCOUNT)).call{ value: 0.1 ether }("");
    }

    function testReceiveOkay() public {
        // Add entry to table
        (, bytes32 orderKey) = ACCOUNT.executeCreateIncreaseOrder{
            value: 0.01 ether
        }(ETH_USD_MARKET, 1e9, 0.01 ether);
        IGmxV2OrderTypes.Props memory o;
        o.addresses.account = address(ACCOUNT);
        IGmxV2EventUtilsTypes.EventLogData memory ev;
        vm.prank(GMX_CONTROLLER);
        ACCOUNT.afterOrderExecution(orderKey, o, ev);
        payable(address(ACCOUNT)).call{ value: 0.1 ether }("");
    }
}

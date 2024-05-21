// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {
    OrderHelpers
} from "../../../../contracts/strategies/gmxFrf/libraries/OrderHelpers.sol";
import {
    IGmxV2OrderTypes
} from "../../../../contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";

contract OrderHelpersTest is Test {
    // ============ Setup ============

    function setUp() public {
        // Empty.
    }

    // ============ Create Order Addresses Tests ============

    function testCreateOrderAdresses() public {
        IGmxV2OrderTypes.CreateOrderParamsAddresses
            memory addresses = OrderHelpers.createOrderAddresses(
                msg.sender,
                address(1),
                address(0),
                false
            );
        assertEq(addresses.receiver, address(this));
        assertEq(addresses.callbackContract, address(this));
        assertEq(addresses.uiFeeReceiver, address(0));
        assertEq(addresses.market, msg.sender);
        assertEq(addresses.initialCollateralToken, address(1));
        assertEq(addresses.swapPath.length, 0);
    }

    function testCreateOrderAdressesSwap() public {
        IGmxV2OrderTypes.CreateOrderParamsAddresses
            memory addresses = OrderHelpers.createOrderAddresses(
                msg.sender,
                address(1),
                address(0),
                true
            );
        assertEq(addresses.receiver, address(this));
        assertEq(addresses.callbackContract, address(this));
        assertEq(addresses.uiFeeReceiver, address(0));
        assertEq(addresses.market, msg.sender);
        assertEq(addresses.initialCollateralToken, address(1));
        assertEq(addresses.swapPath.length, 1);
        assertEq(addresses.swapPath[0], msg.sender);
    }

    // ============ Get Minimum Swap Output With Slippage Tests ============

    function testGetMinimumSwapOutputWithSlippageZeroSlippage() public {
        assertEq(OrderHelpers.getMinimumSwapOutputWithSlippage(100, 0), 100);
    }

    function testGetMinimumSwapOutputWithSlippage() public {
        assertEq(OrderHelpers.getMinimumSwapOutputWithSlippage(100, 5e17), 50);
    }

    // ============ Get Minimum Acceptable Price For Increase Tests ============

    function testGetMinimumAcceptablePriceForIncreaseZero() public {
        assertEq(
            OrderHelpers.getMinimumAcceptablePriceForIncrease(100, 0),
            100
        );
    }

    function testGetMinimumAcceptablePriceForIncrease() public {
        assertEq(
            OrderHelpers.getMinimumAcceptablePriceForIncrease(100, 5e17),
            50
        );
    }

    // ============ Get Maximum Acceptable Price For Decrease Tests ============

    function testGetMaximumAcceptablePriceForDecreaseZero() public {
        assertEq(
            OrderHelpers.getMaximumAcceptablePriceForDecrease(100, 0),
            100
        );
    }

    function testGetMaximumAcceptablePriceForDecrease() public {
        assertEq(
            OrderHelpers.getMaximumAcceptablePriceForDecrease(100, 5e17),
            150
        );
    }
}

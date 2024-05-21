// SPDX-License-Identifier: BUSL-1.1

// Borrowed from https://github.com/gmx-io/gmx-synthetics/blob/178290846694d65296a14b9f4b6ff9beae28a7f7/contracts/order/OrderStoreUtils.sol
// Modified as follows:
// - GoldLink types
// - set functions removed
// - additional getters like getting keys for storage values

pragma solidity ^0.8.0;

import { Keys } from "../keys/Keys.sol";
import {
    IGmxV2DataStore
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import { IGmxV2OrderTypes } from "../interfaces/external/IGmxV2OrderTypes.sol";
import { Order } from "./Order.sol";

library OrderStoreUtils {
    using Order for IGmxV2OrderTypes.Props;

    // ============ Constants ============

    bytes32 public constant ACCOUNT = keccak256(abi.encode("ACCOUNT"));
    bytes32 public constant RECEIVER = keccak256(abi.encode("RECEIVER"));
    bytes32 public constant CALLBACK_CONTRACT =
        keccak256(abi.encode("CALLBACK_CONTRACT"));
    bytes32 public constant UI_FEE_RECEIVER =
        keccak256(abi.encode("UI_FEE_RECEIVER"));
    bytes32 public constant MARKET = keccak256(abi.encode("MARKET"));
    bytes32 public constant INITIAL_COLLATERAL_TOKEN =
        keccak256(abi.encode("INITIAL_COLLATERAL_TOKEN"));
    bytes32 public constant SWAP_PATH = keccak256(abi.encode("SWAP_PATH"));

    bytes32 public constant ORDER_TYPE = keccak256(abi.encode("ORDER_TYPE"));
    bytes32 public constant DECREASE_POSITION_SWAP_TYPE =
        keccak256(abi.encode("DECREASE_POSITION_SWAP_TYPE"));
    bytes32 public constant SIZE_DELTA_USD =
        keccak256(abi.encode("SIZE_DELTA_USD"));
    bytes32 public constant INITIAL_COLLATERAL_DELTA_AMOUNT =
        keccak256(abi.encode("INITIAL_COLLATERAL_DELTA_AMOUNT"));
    bytes32 public constant TRIGGER_PRICE =
        keccak256(abi.encode("TRIGGER_PRICE"));
    bytes32 public constant ACCEPTABLE_PRICE =
        keccak256(abi.encode("ACCEPTABLE_PRICE"));
    bytes32 public constant EXECUTION_FEE =
        keccak256(abi.encode("EXECUTION_FEE"));
    bytes32 public constant CALLBACK_GAS_LIMIT =
        keccak256(abi.encode("CALLBACK_GAS_LIMIT"));
    bytes32 public constant MIN_OUTPUT_AMOUNT =
        keccak256(abi.encode("MIN_OUTPUT_AMOUNT"));
    bytes32 public constant UPDATED_AT_BLOCK =
        keccak256(abi.encode("UPDATED_AT_BLOCK"));

    bytes32 public constant IS_LONG = keccak256(abi.encode("IS_LONG"));
    bytes32 public constant SHOULD_UNWRAP_NATIVE_TOKEN =
        keccak256(abi.encode("SHOULD_UNWRAP_NATIVE_TOKEN"));
    bytes32 public constant IS_FROZEN = keccak256(abi.encode("IS_FROZEN"));

    // ============ Internal Functions ============

    function get(
        IGmxV2DataStore dataStore,
        bytes32 key
    ) internal view returns (IGmxV2OrderTypes.Props memory) {
        IGmxV2OrderTypes.Props memory order;
        if (!dataStore.containsBytes32(Keys.ORDER_LIST, key)) {
            return order;
        }

        order.setAccount(
            dataStore.getAddress(keccak256(abi.encode(key, ACCOUNT)))
        );

        order.setReceiver(
            dataStore.getAddress(keccak256(abi.encode(key, RECEIVER)))
        );

        order.setCallbackContract(
            dataStore.getAddress(keccak256(abi.encode(key, CALLBACK_CONTRACT)))
        );

        order.setUiFeeReceiver(
            dataStore.getAddress(keccak256(abi.encode(key, UI_FEE_RECEIVER)))
        );

        order.setMarket(
            dataStore.getAddress(keccak256(abi.encode(key, MARKET)))
        );

        order.setInitialCollateralToken(
            dataStore.getAddress(
                keccak256(abi.encode(key, INITIAL_COLLATERAL_TOKEN))
            )
        );

        order.setSwapPath(
            dataStore.getAddressArray(keccak256(abi.encode(key, SWAP_PATH)))
        );

        order.setOrderType(
            IGmxV2OrderTypes.OrderType(
                dataStore.getUint(keccak256(abi.encode(key, ORDER_TYPE)))
            )
        );

        order.setDecreasePositionSwapType(
            IGmxV2OrderTypes.DecreasePositionSwapType(
                dataStore.getUint(
                    keccak256(abi.encode(key, DECREASE_POSITION_SWAP_TYPE))
                )
            )
        );

        order.setSizeDeltaUsd(
            dataStore.getUint(keccak256(abi.encode(key, SIZE_DELTA_USD)))
        );

        order.setInitialCollateralDeltaAmount(
            dataStore.getUint(
                keccak256(abi.encode(key, INITIAL_COLLATERAL_DELTA_AMOUNT))
            )
        );

        order.setTriggerPrice(
            dataStore.getUint(keccak256(abi.encode(key, TRIGGER_PRICE)))
        );

        order.setAcceptablePrice(
            dataStore.getUint(keccak256(abi.encode(key, ACCEPTABLE_PRICE)))
        );

        order.setExecutionFee(
            dataStore.getUint(keccak256(abi.encode(key, EXECUTION_FEE)))
        );

        order.setCallbackGasLimit(
            dataStore.getUint(keccak256(abi.encode(key, CALLBACK_GAS_LIMIT)))
        );

        order.setMinOutputAmount(
            dataStore.getUint(keccak256(abi.encode(key, MIN_OUTPUT_AMOUNT)))
        );

        order.setUpdatedAtBlock(
            dataStore.getUint(keccak256(abi.encode(key, UPDATED_AT_BLOCK)))
        );

        order.setIsLong(dataStore.getBool(keccak256(abi.encode(key, IS_LONG))));

        order.setShouldUnwrapNativeToken(
            dataStore.getBool(
                keccak256(abi.encode(key, SHOULD_UNWRAP_NATIVE_TOKEN))
            )
        );

        order.setIsFrozen(
            dataStore.getBool(keccak256(abi.encode(key, IS_FROZEN)))
        );

        return order;
    }

    function getOrderMarket(
        IGmxV2DataStore dataStore,
        bytes32 key
    ) internal view returns (address) {
        return dataStore.getAddress(keccak256(abi.encode(key, MARKET)));
    }

    function getOrderCount(
        IGmxV2DataStore dataStore
    ) internal view returns (uint256) {
        return dataStore.getBytes32Count(Keys.ORDER_LIST);
    }

    function getOrderKeys(
        IGmxV2DataStore dataStore,
        uint256 start,
        uint256 end
    ) internal view returns (bytes32[] memory) {
        return dataStore.getBytes32ValuesAt(Keys.ORDER_LIST, start, end);
    }

    function getAccountOrderCount(
        IGmxV2DataStore dataStore,
        address account
    ) internal view returns (uint256) {
        return dataStore.getBytes32Count(Keys.accountOrderListKey(account));
    }

    function getAccountOrderKeys(
        IGmxV2DataStore dataStore,
        address account,
        uint256 start,
        uint256 end
    ) internal view returns (bytes32[] memory) {
        return
            dataStore.getBytes32ValuesAt(
                Keys.accountOrderListKey(account),
                start,
                end
            );
    }

    function getAccountOrderKeys(
        IGmxV2DataStore dataStore,
        address account
    ) internal view returns (bytes32[] memory) {
        uint256 orderCount = getAccountOrderCount(dataStore, account);

        return getAccountOrderKeys(dataStore, account, 0, orderCount);
    }

    function getAccountOrders(
        IGmxV2DataStore dataStore,
        address account
    ) internal view returns (IGmxV2OrderTypes.Props[] memory) {
        bytes32[] memory keys = getAccountOrderKeys(dataStore, account);

        IGmxV2OrderTypes.Props[] memory orders = new IGmxV2OrderTypes.Props[](
            keys.length
        );

        uint256 keysLength = keys.length;
        for (uint256 i = 0; i < keysLength; ++i) {
            orders[i] = get(dataStore, keys[i]);
        }

        return orders;
    }

    function getOrderInMarket(
        IGmxV2DataStore dataStore,
        address account,
        address market
    )
        internal
        view
        returns (IGmxV2OrderTypes.Props memory order, bytes32 orderId)
    {
        bytes32[] memory keys = getAccountOrderKeys(dataStore, account);

        uint256 keysLength = keys.length;
        for (uint256 i = 0; i < keysLength; ++i) {
            address orderMarket = getOrderMarket(dataStore, keys[i]);

            if (orderMarket != market) continue;

            return (get(dataStore, keys[i]), keys[i]);
        }
    }
}

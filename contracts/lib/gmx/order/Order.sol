// SPDX-License-Identifier: BUSL-1.1

// Slightly modified version of https://github.com/gmx-io/gmx-synthetics/blob/178290846694d65296a14b9f4b6ff9beae28a7f7/contracts/gas/GasUtils.sol
// Modified as follows:
// - Copied exactly from GMX V2 with structs removed and touch removed

pragma solidity ^0.8.0;

import { IGmxV2OrderTypes } from "../interfaces/external/IGmxV2OrderTypes.sol";

library Order {
    // ============ Internal Functions ============

    // @dev set the order account
    // @param props Props
    // @param value the value to set to
    function setAccount(
        IGmxV2OrderTypes.Props memory props,
        address value
    ) internal pure {
        props.addresses.account = value;
    }

    // @dev the order receiver
    // @param props Props
    // @return the order receiver
    function receiver(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (address) {
        return props.addresses.receiver;
    }

    // @dev set the order receiver
    // @param props Props
    // @param value the value to set to
    function setReceiver(
        IGmxV2OrderTypes.Props memory props,
        address value
    ) internal pure {
        props.addresses.receiver = value;
    }

    // @dev the order callbackContract
    // @param props Props
    // @return the order callbackContract
    function callbackContract(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (address) {
        return props.addresses.callbackContract;
    }

    // @dev set the order callbackContract
    // @param props Props
    // @param value the value to set to
    function setCallbackContract(
        IGmxV2OrderTypes.Props memory props,
        address value
    ) internal pure {
        props.addresses.callbackContract = value;
    }

    // @dev the order market
    // @param props Props
    // @return the order market
    function market(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (address) {
        return props.addresses.market;
    }

    // @dev set the order market
    // @param props Props
    // @param value the value to set to
    function setMarket(
        IGmxV2OrderTypes.Props memory props,
        address value
    ) internal pure {
        props.addresses.market = value;
    }

    // @dev the order initialCollateralToken
    // @param props Props
    // @return the order initialCollateralToken
    function initialCollateralToken(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (address) {
        return props.addresses.initialCollateralToken;
    }

    // @dev set the order initialCollateralToken
    // @param props Props
    // @param value the value to set to
    function setInitialCollateralToken(
        IGmxV2OrderTypes.Props memory props,
        address value
    ) internal pure {
        props.addresses.initialCollateralToken = value;
    }

    // @dev the order uiFeeReceiver
    // @param props Props
    // @return the order uiFeeReceiver
    function uiFeeReceiver(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (address) {
        return props.addresses.uiFeeReceiver;
    }

    // @dev set the order uiFeeReceiver
    // @param props Props
    // @param value the value to set to
    function setUiFeeReceiver(
        IGmxV2OrderTypes.Props memory props,
        address value
    ) internal pure {
        props.addresses.uiFeeReceiver = value;
    }

    // @dev the order swapPath
    // @param props Props
    // @return the order swapPath
    function swapPath(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (address[] memory) {
        return props.addresses.swapPath;
    }

    // @dev set the order swapPath
    // @param props Props
    // @param value the value to set to
    function setSwapPath(
        IGmxV2OrderTypes.Props memory props,
        address[] memory value
    ) internal pure {
        props.addresses.swapPath = value;
    }

    // @dev the order type
    // @param props Props
    // @return the order type
    function orderType(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (IGmxV2OrderTypes.OrderType) {
        return props.numbers.orderType;
    }

    // @dev set the order type
    // @param props Props
    // @param value the value to set to
    function setOrderType(
        IGmxV2OrderTypes.Props memory props,
        IGmxV2OrderTypes.OrderType value
    ) internal pure {
        props.numbers.orderType = value;
    }

    function decreasePositionSwapType(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (IGmxV2OrderTypes.DecreasePositionSwapType) {
        return props.numbers.decreasePositionSwapType;
    }

    function setDecreasePositionSwapType(
        IGmxV2OrderTypes.Props memory props,
        IGmxV2OrderTypes.DecreasePositionSwapType value
    ) internal pure {
        props.numbers.decreasePositionSwapType = value;
    }

    // @dev the order sizeDeltaUsd
    // @param props Props
    // @return the order sizeDeltaUsd
    function sizeDeltaUsd(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.sizeDeltaUsd;
    }

    // @dev set the order sizeDeltaUsd
    // @param props Props
    // @param value the value to set to
    function setSizeDeltaUsd(
        IGmxV2OrderTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.sizeDeltaUsd = value;
    }

    // @dev the order initialCollateralDeltaAmount
    // @param props Props
    // @return the order initialCollateralDeltaAmount
    function initialCollateralDeltaAmount(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.initialCollateralDeltaAmount;
    }

    // @dev set the order initialCollateralDeltaAmount
    // @param props Props
    // @param value the value to set to
    function setInitialCollateralDeltaAmount(
        IGmxV2OrderTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.initialCollateralDeltaAmount = value;
    }

    // @dev the order triggerPrice
    // @param props Props
    // @return the order triggerPrice
    function triggerPrice(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.triggerPrice;
    }

    // @dev set the order triggerPrice
    // @param props Props
    // @param value the value to set to
    function setTriggerPrice(
        IGmxV2OrderTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.triggerPrice = value;
    }

    // @dev the order acceptablePrice
    // @param props Props
    // @return the order acceptablePrice
    function acceptablePrice(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.acceptablePrice;
    }

    // @dev set the order acceptablePrice
    // @param props Props
    // @param value the value to set to
    function setAcceptablePrice(
        IGmxV2OrderTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.acceptablePrice = value;
    }

    // @dev set the order executionFee
    // @param props Props
    // @param value the value to set to
    function setExecutionFee(
        IGmxV2OrderTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.executionFee = value;
    }

    // @dev the order executionFee
    // @param props Props
    // @return the order executionFee
    function executionFee(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.executionFee;
    }

    // @dev the order callbackGasLimit
    // @param props Props
    // @return the order callbackGasLimit
    function callbackGasLimit(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.callbackGasLimit;
    }

    // @dev set the order callbackGasLimit
    // @param props Props
    // @param value the value to set to
    function setCallbackGasLimit(
        IGmxV2OrderTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.callbackGasLimit = value;
    }

    // @dev the order minOutputAmount
    // @param props Props
    // @return the order minOutputAmount
    function minOutputAmount(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.minOutputAmount;
    }

    // @dev set the order minOutputAmount
    // @param props Props
    // @param value the value to set to
    function setMinOutputAmount(
        IGmxV2OrderTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.minOutputAmount = value;
    }

    // @dev the order updatedAtBlock
    // @param props Props
    // @return the order updatedAtBlock
    function updatedAtBlock(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.updatedAtBlock;
    }

    // @dev set the order updatedAtBlock
    // @param props Props
    // @param value the value to set to
    function setUpdatedAtBlock(
        IGmxV2OrderTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.updatedAtBlock = value;
    }

    // @dev whether the order is for a long or short
    // @param props Props
    // @return whether the order is for a long or short
    function isLong(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (bool) {
        return props.flags.isLong;
    }

    // @dev set whether the order is for a long or short
    // @param props Props
    // @param value the value to set to
    function setIsLong(
        IGmxV2OrderTypes.Props memory props,
        bool value
    ) internal pure {
        props.flags.isLong = value;
    }

    // @dev whether to unwrap the native token before transfers to the user
    // @param props Props
    // @return whether to unwrap the native token before transfers to the user
    function shouldUnwrapNativeToken(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (bool) {
        return props.flags.shouldUnwrapNativeToken;
    }

    // @dev set whether the native token should be unwrapped before being
    // transferred to the receiver
    // @param props Props
    // @param value the value to set to
    function setShouldUnwrapNativeToken(
        IGmxV2OrderTypes.Props memory props,
        bool value
    ) internal pure {
        props.flags.shouldUnwrapNativeToken = value;
    }

    // @dev whether the order is frozen
    // @param props Props
    // @return whether the order is frozen
    function isFrozen(
        IGmxV2OrderTypes.Props memory props
    ) internal pure returns (bool) {
        return props.flags.isFrozen;
    }

    // @dev set whether the order is frozen
    // transferred to the receiver
    // @param props Props
    // @param value the value to set to
    function setIsFrozen(
        IGmxV2OrderTypes.Props memory props,
        bool value
    ) internal pure {
        props.flags.isFrozen = value;
    }
}

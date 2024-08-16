// SPDX-License-Identifier: BUSL-1.1

// Borrowed from https://github.com/gmx-io/gmx-synthetics/blob/178290846694d65296a14b9f4b6ff9beae28a7f7/contracts/position/Position.sol
// Modified as follows:
// - GoldLink types
// - removed structs

pragma solidity ^0.8.0;

import {
    IGmxV2PositionTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";

library Position {
    // ============ Internal Functions ============

    function account(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (address) {
        return props.addresses.account;
    }

    function setAccount(
        IGmxV2PositionTypes.Props memory props,
        address value
    ) internal pure {
        props.addresses.account = value;
    }

    function market(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (address) {
        return props.addresses.market;
    }

    function setMarket(
        IGmxV2PositionTypes.Props memory props,
        address value
    ) internal pure {
        props.addresses.market = value;
    }

    function collateralToken(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (address) {
        return props.addresses.collateralToken;
    }

    function setCollateralToken(
        IGmxV2PositionTypes.Props memory props,
        address value
    ) internal pure {
        props.addresses.collateralToken = value;
    }

    function sizeInUsd(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.sizeInUsd;
    }

    function setSizeInUsd(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.sizeInUsd = value;
    }

    function sizeInTokens(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.sizeInTokens;
    }

    function setSizeInTokens(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.sizeInTokens = value;
    }

    function collateralAmount(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.collateralAmount;
    }

    function setCollateralAmount(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.collateralAmount = value;
    }

    function borrowingFactor(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.borrowingFactor;
    }

    function setBorrowingFactor(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.borrowingFactor = value;
    }

    function fundingFeeAmountPerSize(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.fundingFeeAmountPerSize;
    }

    function setFundingFeeAmountPerSize(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.fundingFeeAmountPerSize = value;
    }

    function longTokenClaimableFundingAmountPerSize(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.longTokenClaimableFundingAmountPerSize;
    }

    function setLongTokenClaimableFundingAmountPerSize(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.longTokenClaimableFundingAmountPerSize = value;
    }

    function shortTokenClaimableFundingAmountPerSize(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.shortTokenClaimableFundingAmountPerSize;
    }

    function setShortTokenClaimableFundingAmountPerSize(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.shortTokenClaimableFundingAmountPerSize = value;
    }

    function increasedAtBlock(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.increasedAtBlock;
    }

    function setIncreasedAtBlock(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.increasedAtBlock = value;
    }

    function decreasedAtBlock(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.decreasedAtBlock;
    }

    function setDecreasedAtBlock(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.decreasedAtBlock = value;
    }

    function decreasedAtTime(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.decreasedAtTime;
    }

    function setDecreasedAtTime(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.decreasedAtTime = value;
    }

    function increasedAtTime(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (uint256) {
        return props.numbers.increasedAtTime;
    }

    function setIncreasedAtTime(
        IGmxV2PositionTypes.Props memory props,
        uint256 value
    ) internal pure {
        props.numbers.increasedAtTime = value;
    }

    function isLong(
        IGmxV2PositionTypes.Props memory props
    ) internal pure returns (bool) {
        return props.flags.isLong;
    }

    function setIsLong(
        IGmxV2PositionTypes.Props memory props,
        bool value
    ) internal pure {
        props.flags.isLong = value;
    }
}

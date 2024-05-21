// SPDX-License-Identifier: BUSL-1.1

// Borrowed from https://github.com/gmx-io/gmx-synthetics/blob/178290846694d65296a14b9f4b6ff9beae28a7f7/contracts/position/PositionStoreUtils.sol
// Modified as follows:
// - Removed setters
// - added additional getters

pragma solidity ^0.8.0;

import { Keys } from "../keys/Keys.sol";
import {
    IGmxV2DataStore
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";

import { Position } from "./Position.sol";
import {
    IGmxV2PositionTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";

library PositionStoreUtils {
    using Position for IGmxV2PositionTypes.Props;

    // ============ Constants ============

    bytes32 public constant ACCOUNT = keccak256(abi.encode("ACCOUNT"));
    bytes32 public constant MARKET = keccak256(abi.encode("MARKET"));
    bytes32 public constant COLLATERAL_TOKEN =
        keccak256(abi.encode("COLLATERAL_TOKEN"));

    bytes32 public constant SIZE_IN_USD = keccak256(abi.encode("SIZE_IN_USD"));
    bytes32 public constant SIZE_IN_TOKENS =
        keccak256(abi.encode("SIZE_IN_TOKENS"));
    bytes32 public constant COLLATERAL_AMOUNT =
        keccak256(abi.encode("COLLATERAL_AMOUNT"));
    bytes32 public constant BORROWING_FACTOR =
        keccak256(abi.encode("BORROWING_FACTOR"));
    bytes32 public constant FUNDING_FEE_AMOUNT_PER_SIZE =
        keccak256(abi.encode("FUNDING_FEE_AMOUNT_PER_SIZE"));
    bytes32 public constant LONG_TOKEN_CLAIMABLE_FUNDING_AMOUNT_PER_SIZE =
        keccak256(abi.encode("LONG_TOKEN_CLAIMABLE_FUNDING_AMOUNT_PER_SIZE"));
    bytes32 public constant SHORT_TOKEN_CLAIMABLE_FUNDING_AMOUNT_PER_SIZE =
        keccak256(abi.encode("SHORT_TOKEN_CLAIMABLE_FUNDING_AMOUNT_PER_SIZE"));
    bytes32 public constant INCREASED_AT_BLOCK =
        keccak256(abi.encode("INCREASED_AT_BLOCK"));
    bytes32 public constant DECREASED_AT_BLOCK =
        keccak256(abi.encode("DECREASED_AT_BLOCK"));

    bytes32 public constant IS_LONG = keccak256(abi.encode("IS_LONG"));

    // ============ Internal Functions ============

    function get(
        IGmxV2DataStore dataStore,
        bytes32 key
    ) internal view returns (IGmxV2PositionTypes.Props memory) {
        IGmxV2PositionTypes.Props memory position;
        if (!dataStore.containsBytes32(Keys.POSITION_LIST, key)) {
            return position;
        }

        position.setAccount(
            dataStore.getAddress(keccak256(abi.encode(key, ACCOUNT)))
        );

        position.setMarket(
            dataStore.getAddress(keccak256(abi.encode(key, MARKET)))
        );

        position.setCollateralToken(
            dataStore.getAddress(keccak256(abi.encode(key, COLLATERAL_TOKEN)))
        );

        position.setSizeInUsd(
            dataStore.getUint(keccak256(abi.encode(key, SIZE_IN_USD)))
        );

        position.setSizeInTokens(
            dataStore.getUint(keccak256(abi.encode(key, SIZE_IN_TOKENS)))
        );

        position.setCollateralAmount(
            dataStore.getUint(keccak256(abi.encode(key, COLLATERAL_AMOUNT)))
        );

        position.setBorrowingFactor(
            dataStore.getUint(keccak256(abi.encode(key, BORROWING_FACTOR)))
        );

        position.setFundingFeeAmountPerSize(
            dataStore.getUint(
                keccak256(abi.encode(key, FUNDING_FEE_AMOUNT_PER_SIZE))
            )
        );

        position.setLongTokenClaimableFundingAmountPerSize(
            dataStore.getUint(
                keccak256(
                    abi.encode(
                        key,
                        LONG_TOKEN_CLAIMABLE_FUNDING_AMOUNT_PER_SIZE
                    )
                )
            )
        );

        position.setShortTokenClaimableFundingAmountPerSize(
            dataStore.getUint(
                keccak256(
                    abi.encode(
                        key,
                        SHORT_TOKEN_CLAIMABLE_FUNDING_AMOUNT_PER_SIZE
                    )
                )
            )
        );

        position.setIncreasedAtBlock(
            dataStore.getUint(keccak256(abi.encode(key, INCREASED_AT_BLOCK)))
        );

        position.setDecreasedAtBlock(
            dataStore.getUint(keccak256(abi.encode(key, DECREASED_AT_BLOCK)))
        );

        position.setIsLong(
            dataStore.getBool(keccak256(abi.encode(key, IS_LONG)))
        );

        return position;
    }

    function getPositionCount(
        IGmxV2DataStore dataStore
    ) internal view returns (uint256) {
        return dataStore.getBytes32Count(Keys.POSITION_LIST);
    }

    function getPositionKeys(
        IGmxV2DataStore dataStore,
        uint256 start,
        uint256 end
    ) internal view returns (bytes32[] memory) {
        return dataStore.getBytes32ValuesAt(Keys.POSITION_LIST, start, end);
    }

    function getAccountPositionCount(
        IGmxV2DataStore dataStore,
        address account
    ) internal view returns (uint256) {
        return dataStore.getBytes32Count(Keys.accountPositionListKey(account));
    }

    function getAccountPositionKeys(
        IGmxV2DataStore dataStore,
        address account,
        uint256 start,
        uint256 end
    ) internal view returns (bytes32[] memory) {
        return
            dataStore.getBytes32ValuesAt(
                Keys.accountPositionListKey(account),
                start,
                end
            );
    }

    function getAccountPositionKeys(
        IGmxV2DataStore dataStore,
        address account
    ) internal view returns (bytes32[] memory keys) {
        uint256 positionCount = getAccountPositionCount(dataStore, account);

        return getAccountPositionKeys(dataStore, account, 0, positionCount);
    }

    function getAccountPositions(
        IGmxV2DataStore dataStore,
        address account
    ) internal view returns (IGmxV2PositionTypes.Props[] memory positions) {
        bytes32[] memory keys = getAccountPositionKeys(dataStore, account);

        positions = new IGmxV2PositionTypes.Props[](keys.length);

        uint256 keysLength = keys.length;
        for (uint256 i = 0; i < keysLength; ++i) {
            positions[i] = get(dataStore, keys[i]);
        }
    }

    function getPositionKey(
        address account,
        address market,
        address collateralToken,
        bool isLong
    ) internal pure returns (bytes32) {
        bytes32 key = keccak256(
            abi.encode(account, market, collateralToken, isLong)
        );

        return key;
    }

    function getPositionMarket(
        IGmxV2DataStore dataStore,
        bytes32 key
    ) internal view returns (address) {
        return dataStore.getAddress(keccak256(abi.encode(key, MARKET)));
    }

    function getPositionSizeUsd(
        IGmxV2DataStore dataStore,
        bytes32 key
    ) internal view returns (uint256) {
        return dataStore.getUint(keccak256(abi.encode(key, SIZE_IN_USD)));
    }
}

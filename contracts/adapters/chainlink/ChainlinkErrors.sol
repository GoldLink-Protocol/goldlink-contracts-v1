// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

/**
 * @title ChainlinkErrors
 * @author GoldLink
 *
 * @dev The Chainlink errors library.
 */
library ChainlinkErrors {
    string internal constant INVALID_ASSET_ADDRESS = "Invalid asset address.";
    string internal constant INVALID_ORACLE_ASSET = "Invalid oracle asset.";
    string internal constant ORACLE_REGISTRY_ASSET_NOT_FOUND =
        "OracleRegistry: Asset not found.";
    string internal constant ORACLE_REGISTRY_INVALID_ORACLE =
        "OracleRegistry: Invalid oracle.";

    string internal constant ORACLE_REGISTRY_INVALID_ORACLE_PRICE =
        "OracleRegistry: Invalid oracle price.";
    string
        internal constant ORACLE_REGISTRY_LAST_UPDATE_TIMESTAMP_EXCEEDS_VALID_TIMESTAMP_RANGE =
        "OracleRegistry: Last update timestamp exceeds valid timestamp range.";
}

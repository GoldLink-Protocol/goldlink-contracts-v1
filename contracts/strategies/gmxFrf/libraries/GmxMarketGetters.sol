// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IGmxV2DataStore } from "../interfaces/gmx/IGmxV2DataStore.sol";
import { IGmxV2MarketTypes } from "../interfaces/gmx/IGmxV2MarketTypes.sol";

/**
 * @title GmxMarketGetters
 * @author GoldLink
 *
 * @dev Library for getting values directly for gmx markets.
 */
library GmxMarketGetters {
    // ============ Constants ============

    bytes32 internal constant MARKET_SALT =
        keccak256(abi.encode("MARKET_SALT"));
    bytes32 internal constant MARKET_KEY = keccak256(abi.encode("MARKET_KEY"));
    bytes32 internal constant MARKET_TOKEN =
        keccak256(abi.encode("MARKET_TOKEN"));
    bytes32 internal constant INDEX_TOKEN =
        keccak256(abi.encode("INDEX_TOKEN"));
    bytes32 internal constant LONG_TOKEN = keccak256(abi.encode("LONG_TOKEN"));
    bytes32 internal constant SHORT_TOKEN =
        keccak256(abi.encode("SHORT_TOKEN"));

    // ============ Internal Functions ============

    /**
     * @notice Get the market token for a given market.
     * @param dataStore    The data store being queried for the market token.
     * @param market       The market whose token is being fetched.
     * @return marketToken The token for the market.
     */
    function getMarketToken(
        IGmxV2DataStore dataStore,
        address market
    ) internal view returns (address marketToken) {
        return
            dataStore.getAddress(keccak256(abi.encode(market, MARKET_TOKEN)));
    }

    /**
     * @notice Get the index token for a given market.
     * @param dataStore   The data store being queried for the index token.
     * @param market      The market whose index token is being fetched.
     * @return indexToken The token for the index for a given market.
     */
    function getIndexToken(
        IGmxV2DataStore dataStore,
        address market
    ) internal view returns (address indexToken) {
        return dataStore.getAddress(keccak256(abi.encode(market, INDEX_TOKEN)));
    }

    /**
     * @notice Get the long token for a given market.
     * @param dataStore  The data store being queried for the long token.
     * @param market     The market whose long token is being fetched.
     * @return longToken The token for the long asset for a given market.
     */
    function getLongToken(
        IGmxV2DataStore dataStore,
        address market
    ) internal view returns (address longToken) {
        return dataStore.getAddress(keccak256(abi.encode(market, LONG_TOKEN)));
    }

    /**
     * @notice Get the short token for a given market.
     * @param dataStore   The data store being queried for the short token.
     * @param market      The market whose short token is being fetched.
     * @return shortToken The token for the short asset for a given market.
     */
    function getShortToken(
        IGmxV2DataStore dataStore,
        address market
    ) internal view returns (address shortToken) {
        return dataStore.getAddress(keccak256(abi.encode(market, SHORT_TOKEN)));
    }

    /**
     * @notice Get the short and long tokens for a given market.
     * @param dataStore   The data store being queried for the short and long tokens.
     * @param market      The market whose short and long tokens are being fetched.
     * @return shortToken The token for the short asset for a given market.
     * @return longToken  The token for the long asset for a given market.
     */
    function getMarketTokens(
        IGmxV2DataStore dataStore,
        address market
    ) internal view returns (address shortToken, address longToken) {
        return (
            getShortToken(dataStore, market),
            getLongToken(dataStore, market)
        );
    }

    /**
     * @notice Get the market information for a given market.
     * @param dataStore The data store being queried for the market information.
     * @param market    The market whose market information is being fetched.
     * @return props    The properties of a specific market.
     */
    function getMarket(
        IGmxV2DataStore dataStore,
        address market
    ) internal view returns (IGmxV2MarketTypes.Props memory props) {
        return
            IGmxV2MarketTypes.Props(
                getMarketToken(dataStore, market),
                getIndexToken(dataStore, market),
                getLongToken(dataStore, market),
                getShortToken(dataStore, market)
            );
    }
}

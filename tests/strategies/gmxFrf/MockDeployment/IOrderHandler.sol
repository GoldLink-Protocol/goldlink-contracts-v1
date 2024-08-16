// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// Adapter from https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/exchange/OrderHandler.sol

interface IOrderHandler {
    struct SetPricesParams {
        address[] tokens;
        address[] providers;
        bytes[] data;
    }

    // bid: min price, highest buy price
    // ask: max price, lowest sell price
    struct Report {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint32 expiresAt; // Latest timestamp where the report can be verified onchain
        int192 price; // DON consensus median price, carried to 8 decimal places
        int192 bid; // Simulated price impact of a buy order up to the X% depth of liquidity utilisation
        int192 ask; // Simulated price impact of a sell order up to the X% depth of liquidity utilisation
    }

    function executeOrder(
        bytes32 key,
        SetPricesParams calldata oracleParams
    ) external;
}

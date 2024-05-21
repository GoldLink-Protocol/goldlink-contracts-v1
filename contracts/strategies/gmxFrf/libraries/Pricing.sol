// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    IGmxFrfStrategyManager
} from "../interfaces/IGmxFrfStrategyManager.sol";

/**
 * @title Pricing
 * @author GoldLink
 *
 * @dev Library for price conversion for getting the GMX price and USDC price.
 * The internal GMX account system uses 30 decimals to represent USD prices per unit of the underlying token.
 * Example from the GMX documentation:
 * The price of ETH is 5000, and ETH has 18 decimals.
 * The price of one unit of ETH is 5000 / (10 ^ 18), 5 * (10 ^ -15).
 * To handle the decimals, multiply the value by (10 ^ 30).
 * Price would be stored as 5000 / (10 ^ 18) * (10 ^ 30) => 5000 * (10 ^ 12).
 * To read more, see GMX's documentation on oracle prices: https://github.com/gmx-io/gmx-synthetics?tab=readme-ov-file#oracle-prices
 */
library Pricing {
    // ============ Constants ============

    /// @dev The number of decimals used to represent USD within GMX.
    uint256 internal constant USD_DECIMALS = 30;

    // ============ Internal Functions ============

    /**
     * @notice Get the value of an ERC20 token in USD.
     * @param oracle      The `IGmxFrfStrategyManager` to use for the valuation.
     * @param asset       The address of the ERC20 token to evaluate. The asset must have a valid oracle registered within the `IChainlinkAdapter`.
     * @param tokenAmount The token amount to get the valuation for.
     * @return assetValue The value of the token amount in USD.
     */
    function getTokenValueUSD(
        IGmxFrfStrategyManager oracle,
        address asset,
        uint256 tokenAmount
    ) internal view returns (uint256 assetValue) {
        // Exit early if the token amount is 0.
        if (tokenAmount == 0) {
            return 0;
        }

        // Query the oracle for the price of the asset.
        uint256 assetPrice = getUnitTokenPriceUSD(oracle, asset);

        return getTokenValueUSD(tokenAmount, assetPrice);
    }

    /**
     * @notice Get the value of an ERC20 token in USD.
     * @param  tokenAmount The token amount to get the valuation for.
     * @param  price       The price of the token in USD. (1 USD = 1e30).
     * @return assetValue  The value of the token amount in USD.
     * @dev The provided  `IChainlinkAdapter` MUST have a price precision of 30.
     */
    function getTokenValueUSD(
        uint256 tokenAmount,
        uint256 price
    ) internal pure returns (uint256 assetValue) {
        // Per the GMX documentation, the value of a token in terms of USD is simply calculated via multiplication.
        // This is because the USD price already inherently accounts for the decimals of the token.
        return price * tokenAmount;
    }

    /**
     * @notice Gets the price of a given token per unit in USD. USD is represented with 30 decimals of precision.
     * @param oracle      The `IChainlinkAdapter` to use for pricing this token.
     * @param token       The address of the ERC20 token to evaluate. The asset must have a valid oracle registered within the `IChainlinkAdapter`.
     * @return assetValue The value of the token amount in USD.
     */
    function getUnitTokenPriceUSD(
        IGmxFrfStrategyManager oracle,
        address token
    ) internal view returns (uint256) {
        (uint256 price, uint256 oracleDecimals) = oracle.getAssetPrice(token);

        // The total decimals that the price is represented with, which includes both the oracle's
        // decimals and the token's decimals.
        uint256 totalPriceDecimals = oracleDecimals + getAssetDecimals(token);

        // The offset in decimals between the USD price and the the both the oracle's decimals and the token's decimals.
        uint256 decimalOffset = Math.max(USD_DECIMALS, totalPriceDecimals) -
            Math.min(USD_DECIMALS, totalPriceDecimals);

        return
            (USD_DECIMALS >= totalPriceDecimals)
                ? price * (10 ** decimalOffset)
                : price / (10 ** decimalOffset);
    }

    /**
     * @notice Get the amount of a token that is equivalent to a given USD amount based on `token's` current oracle price.
     * @param oracle       The `IChainlinkAdapter` to use for querying the oracle price for this token.
     * @param token        The token address for the token to quote `usdAmount` in.
     * @param usdAmount    The amount in USD to convert to tokens. (1 usd = 1^30)
     * @return tokenAmount The amount of `token` equivalent to `usdAmount` based on the current `oracle` price.
     */
    function getTokenAmountForUSD(
        IGmxFrfStrategyManager oracle,
        address token,
        uint256 usdAmount
    ) internal view returns (uint256) {
        uint256 assetPrice = getUnitTokenPriceUSD(oracle, token);

        // As defined per the GMX documentation, the value of a token in terms of USD is simply calculated via division.
        return usdAmount / assetPrice;
    }

    /**
     * @notice Fetch decimals for an asset.
     * @param token     The token to get the decimals for.
     * @return decimals The decimals of the token.
     */
    function getAssetDecimals(
        address token
    ) internal view returns (uint256 decimals) {
        return IERC20Metadata(token).decimals();
    }
}

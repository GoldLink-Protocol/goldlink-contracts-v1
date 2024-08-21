// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    IGmxFrfStrategyManager
} from "../interfaces/IGmxFrfStrategyManager.sol";
import { GmxStorageGetters } from "./GmxStorageGetters.sol";
import { GmxMarketGetters } from "./GmxMarketGetters.sol";

/**
 * @title ClaimLogic
 * @author GoldLink
 *
 * @dev Logic for handling collateral and funding fee claims for a given account.
 */
library ClaimLogic {
    // ============ External Functions ============

    /**
     * @notice Claims collateral in a given market in the event a collateral stipend is issued to an account. When collateral is locked in a claim due to high price impact,
     * the GMX team reviews the case and determines whether or not collateral can be claimed based on if the cause of the price impact was malicious or not. If collateral is locked in a claim,
     * it is impossible to determine its value until the GMX team decides on the refund, which can take up to 14 days. As a result, an account that causes a collateral claim can be liquidated due to
     * this loss in value. To account for this, the timestamp of the most recent liquidation is recorded for an account. If, when providing the `timeKey` for the collateral claim, the timestamp
     * of the claim falls before the most recent liquidation, then the claimed funds are sent to the Goldlink claims distribution account to properly distribute the funds.
     * This logic is in place to ensure that if collateral is locked in a claim, resulting in an account liquidation, the borrower cannot later claim these assets. Collateral
     * claims should rarely occur due to Goldlink's maximum slippage configuration, but are still possible in the event GMX changes the maximum price impact threshold.
     */
    function claimCollateral(
        IGmxFrfStrategyManager manager,
        address market,
        address asset,
        uint256 timeKey,
        uint256 lastLiquidationTimestamp
    ) external {
        uint256 divisor = GmxStorageGetters.getClaimableCollateralTimeDivisor(
            manager.gmxV2DataStore()
        );
        // This is the floored timestamp of when collateral lock-up occurred due to excessive price impact.
        // Due to the underestimate, it is possible (but extremely unlikely) that collateral could erroneously
        // be allocated to the distributor account, when it should have been allocated to the strategy account.
        uint256 initialClaimTimestamp = timeKey * divisor;

        address recipient = address(this);

        if (initialClaimTimestamp <= lastLiquidationTimestamp) {
            recipient = manager.COLLATERAL_CLAIM_DISTRIBUTOR();
        }

        address[] memory markets = new address[](1);
        address[] memory assets = new address[](1);
        uint256[] memory timeKeys = new uint256[](1);

        markets[0] = market;
        assets[0] = asset;
        timeKeys[0] = timeKey;

        // This function will transfer the claimable collateral to the reciever in the event that claimable collateral exists for the given (market, asset, timekey).
        // The function will revert if no such collateral exists.
        manager.gmxV2ExchangeRouter().claimCollateral(
            markets,
            assets,
            timeKeys,
            recipient
        );
    }

    /**
     * @notice Helper method to claim funding fees in a specified market. Claims both long and short funding fees.
     * This method does not impact `unsettled` funding fees.
     * @param manager The configuration manager for the strategy.
     * @param market  The market to claim fees in.
     */
    function claimFundingFeesInMarket(
        IGmxFrfStrategyManager manager,
        address market
    ) external {
        (address shortToken, address longToken) = GmxMarketGetters
            .getMarketTokens(manager.gmxV2DataStore(), market);

        address[] memory markets = new address[](2);
        address[] memory assets = new address[](2);

        markets[0] = market;
        markets[1] = market;

        assets[0] = shortToken;
        assets[1] = longToken;

        claimFundingFees(manager, markets, assets);
    }

    // ============ Public Functions ============

    /**
     * @notice Claim funding fees in all markets for an account.
     * @param manager         The configuration manager for the strategy.
     * @param markets         List of markets to claim funding fees in. Must be in the same order as `tokens`.
     * @param tokens          List of tokens to claim funding fees in. Must be in the same order as `markets`.
     * @return claimedAmounts The amounts of funding fees claimed in each market and for each token, aligned with the indicies of the original input arrays.
     */
    function claimFundingFees(
        IGmxFrfStrategyManager manager,
        address[] memory markets,
        address[] memory tokens
    ) public returns (uint256[] memory claimedAmounts) {
        return
            manager.gmxV2ExchangeRouter().claimFundingFees(
                markets,
                tokens,
                address(this)
            );
    }
}

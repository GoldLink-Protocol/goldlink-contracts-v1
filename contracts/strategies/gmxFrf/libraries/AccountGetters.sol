// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IGmxV2PositionTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";
import {
    IGmxV2PriceTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2PriceTypes.sol";
import {
    GmxMarketGetters
} from "../../../strategies/gmxFrf/libraries/GmxMarketGetters.sol";
import {
    IGmxV2Reader
} from "../../../lib/gmx/interfaces/external/IGmxV2Reader.sol";
import {
    IGmxV2OrderTypes
} from "../../../lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import {
    IGmxV2DataStore
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2MarketTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2MarketTypes.sol";
import {
    IChainlinkAdapter
} from "../../../adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import { IMarketConfiguration } from "../interfaces/IMarketConfiguration.sol";
import { PercentMath } from "../../../libraries/PercentMath.sol";
import {
    PositionStoreUtils
} from "../../../lib/gmx/position/PositionStoreUtils.sol";
import { OrderStoreUtils } from "../../../lib/gmx/order/OrderStoreUtils.sol";
import { Pricing } from "../libraries/Pricing.sol";
import { DeltaConvergenceMath } from "../libraries/DeltaConvergenceMath.sol";
import {
    IGmxFrfStrategyManager
} from "../interfaces/IGmxFrfStrategyManager.sol";
import { Order } from "../../../lib/gmx/order/Order.sol";
import { GmxStorageGetters } from "./GmxStorageGetters.sol";

/**
 * @title AccountGetters
 * @author GoldLink
 *
 * @dev Manages all orders that flow through this account. This includes order execution,
 * cancellation, and freezing. This is required because the
 */
library AccountGetters {
    using PercentMath for uint256;
    using Order for IGmxV2OrderTypes.Props;

    // ============ External Functions ============

    /**
     * @notice Get the total value of the account in terms of USDC.
     * @param manager             The configuration manager for the strategy.
     * @param account             The account to get the value of
     * @return strategyAssetValue The value of a position in terms of USDC.
     */
    function getAccountValueUsdc(
        IGmxFrfStrategyManager manager,
        address account
    ) external view returns (uint256 strategyAssetValue) {
        // First we get the value in USD, since our oracles are priced in USD. Then
        // we can use the USDC oracle price to get the value in USDC.
        uint256 valueUSD = 0;

        // Add the value of ERC-20 tokens held by this account. We do not count native tokens
        // since this can be misleading in cases where liquidators are paying an execution fee.
        valueUSD += _getAccountTokenValueUSD(manager, account);
        // Get the value of all positions that currently exist.
        valueUSD += getAccountPositionsValueUSD(manager, account);
        // Get the values of the orders that are currently active. This only applies to increase orders,
        // because the value of decreases orders is reflected in the position.
        valueUSD += getAccountOrdersValueUSD(manager, account);
        // Get the value of all settled funding fees.
        valueUSD += getSettledFundingFeesValueUSD(manager, account);

        // Since the strategy asset is USDC, return the value of these assets in terms of USDC. This converts from USD -> USDC.
        // This is neccesary for borrower accounting to function properly, as the bank is unware of GMX-specific USD.
        return
            Pricing.getTokenAmountForUSD(
                manager,
                address(manager.USDC()),
                valueUSD
            );
    }

    /**
     * @notice Implements is liquidation finished, validating:
     * 1. There are no pending orders for the account.
     * 2. There are no open positions for the account.
     * 3. There are no unclaimed funding fees for the acocunt.
     * 4. The long token balance of this account is below the dust threshold for the market.
     * @param manager   The configuration manager for the strategy.
     * @param account   The account to check whether the liquidation is finished.
     * @return finished If the liquidation is finished and the `StrategyBank` can now execute
     * the liquidation, returning funds to lenders.
     */
    function isLiquidationFinished(
        IGmxFrfStrategyManager manager,
        address account
    ) external view returns (bool) {
        IGmxV2DataStore dataStore = manager.gmxV2DataStore();

        {
            // Check to make sure there are zero pending orders. This is important in the event that the borrower had an active order, and before
            // the keeper finishes executed the order, a liquidation was both initiated and processed.
            uint256 orderCount = OrderStoreUtils.getAccountOrderCount(
                dataStore,
                account
            );
            if (orderCount != 0) {
                return false;
            }
        }

        // All positions must be liquidated before the liquidation is finished. If an account is allowed to repay its debts while still having active positions,
        // then lenders may not recieve all of their funds back.
        uint256 positionCount = PositionStoreUtils.getAccountPositionCount(
            dataStore,
            account
        );
        if (positionCount != 0) {
            return false;
        }

        // Get all available markets to check funding fees for.
        address[] memory markets = manager.getAvailableMarkets();

        uint256 marketsLength = markets.length;
        for (uint256 i = 0; i < marketsLength; ++i) {
            (address shortToken, address longToken) = GmxMarketGetters
                .getMarketTokens(dataStore, markets[i]);

            // If there are unclaimed short tokens that are owed to the account, these must be claimed as they can directly be paid back to lenders
            // and therefore must be accounted for in the liquidation process. The `minimumSwapRebalanceSize` is not used here because external actors cannot
            // force unclaimed funding fees to be non zero.
            uint256 unclaimedShortTokens = GmxStorageGetters
                .getClaimableFundingFees(
                    dataStore,
                    markets[i],
                    shortToken,
                    account
                );
            if (unclaimedShortTokens != 0) {
                return false;
            }

            uint256 unclaimedLongTokens = GmxStorageGetters
                .getClaimableFundingFees(
                    dataStore,
                    markets[i],
                    longToken,
                    account
                );

            IMarketConfiguration.UnwindParameters memory unwindConfig = manager
                .getMarketUnwindConfiguration(markets[i]);

            // It would be possible to prevent liquidation by continuously sending tokens to the account, so we use the configured "dust threshold" to
            // determine if the tokens held by the account have any meaningful value. The two are combined because otherwise this may result in forcing a liquidator
            // to claim funding fees, just to have the `minSwapRebalanceSize` check to pass.
            if (
                IERC20(longToken).balanceOf(account) + unclaimedLongTokens >=
                unwindConfig.minSwapRebalanceSize
            ) {
                return false;
            }
        }

        // Since there are no remaining positions, no remaining orders,  and the token balances of the account + unclaimed funding fees
        // are below the minimum swap rebalance size, the liquidation is finished.
        return true;
    }

    // ============ Public Functions ============

    /**
     * @notice Get account orders value USD, the USD value of all account orders. The value of an order only relates to the actual assets associated with it, not
     * the size of the order itself. This implies the only orders that have a value > 0 are increase orders, because the initial collateral is locked into the order.
     * Decrease orders have zero value because the value they produce is accounted for in the position pnl/collateral value.
     * @param manager     The configuration manager for the strategy.
     * @param account     The account to get the orders value for.
     * @return totalValue The USD value of all account orders.
     */
    function getAccountOrdersValueUSD(
        IGmxFrfStrategyManager manager,
        address account
    ) public view returns (uint256 totalValue) {
        // Get the keys of all account orders.
        bytes32[] memory accountOrderKeys = OrderStoreUtils.getAccountOrderKeys(
            manager.gmxV2DataStore(),
            account
        );

        // Iterate through all account orders and sum `totalValue`.
        uint256 accountOrderKeysLength = accountOrderKeys.length;
        for (uint256 i = 0; i < accountOrderKeysLength; ++i) {
            totalValue += getOrderValueUSD(manager, accountOrderKeys[i]);
        }

        return totalValue;
    }

    /**
     * @notice Get the order associated with `orderId` 's value in terms of USD. The value of any non-increase order is 0, and the value of an increase order is simply the value
     * of the initial collateral.
     * @param manager        The configuration manager for the strategy.
     * @param orderId        The id of the order to get the value of in USD.
     * @return orderValueUSD The value of the order in USD.
     */
    function getOrderValueUSD(
        IGmxFrfStrategyManager manager,
        bytes32 orderId
    ) public view returns (uint256 orderValueUSD) {
        IGmxV2DataStore dataStore = manager.gmxV2DataStore();

        IGmxV2OrderTypes.Props memory order = OrderStoreUtils.get(
            dataStore,
            orderId
        );

        // If an increase order exists and has not yet been executed, include the value in the account's value,
        // since the order will contain a portion of the USDC that the account is entitled to. Otherwise, the value of the order
        // is 0.
        if (order.orderType() != IGmxV2OrderTypes.OrderType.MarketIncrease) {
            return 0;
        }

        // If an order exists and has not yet been executed, the best we can do to get the value of
        // the order is to get the value of the initial collateral.
        return
            Pricing.getTokenValueUSD(
                manager,
                order.addresses.initialCollateralToken,
                order.numbers.initialCollateralDeltaAmount
            );
    }

    /**
     * @notice Get the value of all positions in USD for an account.
     * @param manager     The configuration manager for the strategy.
     * @param account     The account of to value positions for.
     * @return totalValue The value of all positions in USD for this account.
     */
    function getAccountPositionsValueUSD(
        IGmxFrfStrategyManager manager,
        address account
    ) public view returns (uint256 totalValue) {
        // Get all possible markets this account can have a position in.
        address[] memory availableMarkets = manager.getAvailableMarkets();

        // Iterate over all positions for this account and add value of each position.
        uint256 availableMarketsLength = availableMarkets.length;
        for (uint256 i = 0; i < availableMarketsLength; ++i) {
            totalValue += getPositionValue(
                manager,
                account,
                availableMarkets[i]
            );
        }

        return totalValue;
    }

    /**
     * @notice Get the value of a position in USD.
     * @param manager   The configuration manager for the strategy.
     * @param account   The account the get the position in `market`'s value for.
     * @param market    The market to get the value of the position for.
     * @return valueUSD The value of the position in USD.
     */
    function getPositionValue(
        IGmxFrfStrategyManager manager,
        address account,
        address market
    ) public view returns (uint256 valueUSD) {
        return
            DeltaConvergenceMath.getPositionValueUSD(manager, account, market);
    }

    /**
     * @notice Get the value of all account claims in terms of USD. This calculates the value of all unclaimed, settled funding fees for the account.
     * This method does NOT include the value of collateral claims, as collateral claims cannot be indexed on chain.
     * @param manager   The configuration manager for the strategy.
     * @param account   The account to get the claimable funding fees value for.
     * @return valueUSD The value of all funding fees in USD for the account.
     */
    function getSettledFundingFeesValueUSD(
        IGmxFrfStrategyManager manager,
        address account
    ) public view returns (uint256 valueUSD) {
        address[] memory availableMarkets = manager.getAvailableMarkets();
        IGmxV2DataStore dataStore = manager.gmxV2DataStore();

        // Iterate through all available markets and sum claimable fees.
        // If there is no position, `valueUSD` will be zero.
        uint256 availableMarketsLength = availableMarkets.length;
        for (uint256 i = 0; i < availableMarketsLength; ++i) {
            address market = availableMarkets[i];

            (address shortToken, address longToken) = GmxMarketGetters
                .getMarketTokens(dataStore, market);

            // This returns the total of the unclaimed, settled funding fees. These are positive funding fees that are accrued when a position is decreased.
            // It is important to note that these are only a subset of the position's total funding fees, as there exist unclaimed fees that must also be
            // accounted for within the position.
            (
                uint256 shortFeesClaimable,
                uint256 longFeesClaimable
            ) = getSettledFundingFees(
                    dataStore,
                    account,
                    availableMarkets[i],
                    shortToken,
                    longToken
                );

            // Short and long funding fees earned by the position are not claimable until they
            // are settled. Settlement occurs when the position size is decreased, which can occur in
            // `executeDecreasePosition`, `executeSettleFundingFees`, `executeLiquidatePosition`, `executeReleveragePosition`,
            // and `executeRebalancePosition`. Settlement is triggered any time the position size is decreased.  Once fees are settled,
            // they can be claimed by the account immediately and do not require keeper execution.
            valueUSD += Pricing.getTokenValueUSD(
                manager,
                shortToken,
                shortFeesClaimable
            );

            valueUSD += Pricing.getTokenValueUSD(
                manager,
                longToken,
                longFeesClaimable
            );
        }
    }

    /**
     * @notice Get the settked funding fees for an account for a specific market. These are funding fees
     * that have yet to be claimed by the account, but have already been settled.
     * @param dataStore                The data store to fetch claimable fees from.
     * @param account                  The account to check claimable funding fees for.
     * @param market                   The market the fees are for.
     * @param shortToken               The short token for the market to check claimable fees for.
     * @param longToken                The long token for the market to check claimable fees for.
     * @return shortTokenAmountSettled The amount of settled short token fees owed to this account.
     * @return longTokenAmountSettled  The amount of settled long token fees owed to this account.
     */
    function getSettledFundingFees(
        IGmxV2DataStore dataStore,
        address account,
        address market,
        address shortToken,
        address longToken
    )
        public
        view
        returns (
            uint256 shortTokenAmountSettled,
            uint256 longTokenAmountSettled
        )
    {
        // Get short and long amount claimable.
        shortTokenAmountSettled = GmxStorageGetters.getClaimableFundingFees(
            dataStore,
            market,
            shortToken,
            account
        );
        longTokenAmountSettled = GmxStorageGetters.getClaimableFundingFees(
            dataStore,
            market,
            longToken,
            account
        );

        return (shortTokenAmountSettled, longTokenAmountSettled);
    }

    // ============ Private Functions ============

    /**
     * @notice Calculates the valuation of all ERC20 assets in an account.
     * @param manager       The `GmxFrfStrategyManager` to use.
     * @param account       The account to calculate the valuation for.
     * @return accountValue The total value of the account in USD.
     */
    function _getAccountTokenValueUSD(
        IGmxFrfStrategyManager manager,
        address account
    ) private view returns (uint256 accountValue) {
        // Load in all registered assets.
        address[] memory assets = manager.getRegisteredAssets();

        // Iterate through all registered assets and sum account value.
        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; ++i) {
            address asset = assets[i];

            // Get the balance of the asset in the account.
            uint256 assetBalance = IERC20(asset).balanceOf(account);

            // Increase total account value by asset value in USD.
            accountValue += Pricing.getTokenValueUSD(
                manager,
                asset,
                assetBalance
            );
        }
    }
}

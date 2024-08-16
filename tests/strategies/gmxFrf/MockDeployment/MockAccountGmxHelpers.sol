// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {
    IMarketConfiguration
} from "@contracts/strategies/gmxFrf/interfaces/IMarketConfiguration.sol";
import {
    IGmxV2Reader
} from "@contracts/lib/gmx/interfaces/external/IGmxV2Reader.sol";
import { MockAccountSetup } from "./MockAccountSetup.sol";
import {
    IGmxV2OrderTypes
} from "../../../../contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import {
    IGmxV2MarketTypes
} from "../../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2MarketTypes.sol";
import {
    IGmxV2PriceTypes
} from "@contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2PriceTypes.sol";
import { IOrderHandler } from "./IOrderHandler.sol";
import {
    GmxMarketGetters
} from "../../../../contracts/strategies/gmxFrf/libraries/GmxMarketGetters.sol";
import {
    DeltaConvergenceMath
} from "@contracts/strategies/gmxFrf/libraries/DeltaConvergenceMath.sol";
import {
    Pricing
} from "../../../../contracts/strategies/gmxFrf/libraries/Pricing.sol";
import {
    IGmxV2DataStore
} from "@contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    PositionStoreUtils
} from "@contracts/lib/gmx/position/PositionStoreUtils.sol";
import {
    IGmxV2PositionTypes
} from "@contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";

abstract contract MockAccountGmxHelpers is MockAccountSetup {
    function _expectRevert(string memory revertMsg) internal {
        vm.expectRevert(bytes(revertMsg));
    }

    function _checkOrderAddresses(
        IGmxV2OrderTypes.CreateOrderParamsAddresses memory addrs,
        address market,
        address initialToken
    ) internal view {
        assert(addrs.receiver == address(ACCOUNT));
        assert(addrs.cancellationReceiver == address(ACCOUNT));
        assert(addrs.callbackContract == address(ACCOUNT));
        assert(addrs.uiFeeReceiver == MSIG);
        assert(addrs.market == market);
        assert(addrs.initialCollateralToken == initialToken);
        assert(addrs.swapPath.length == 1);
        assert(addrs.swapPath[0] == market);
    }

    function _getAccountPositionDeltaNumber(
        address account,
        address market
    ) internal view returns (uint256) {
        DeltaConvergenceMath.PositionTokenBreakdown
            memory breakdown = DeltaConvergenceMath.getAccountMarketDelta(
                MANAGER,
                account,
                market,
                0,
                true
            );
        (uint256 delta, ) = DeltaConvergenceMath.getDeltaProportion(
            breakdown.tokensLong,
            breakdown.tokensShort
        );
        return delta;
    }

    function _checkDeltaInRange(
        address account,
        address market
    ) internal view returns (bool) {
        uint256 positionDelta = _getAccountPositionDeltaNumber(account, market);
        IMarketConfiguration.UnwindParameters memory unwindConfig = MANAGER
            .getMarketUnwindConfiguration(market);
        return positionDelta <= unwindConfig.maxDeltaProportion;
    }

    function _logInt256(string memory label, int256 value) internal view {
        if (value < 0) {
            console.log(label, " -", uint256(-value));
        } else {
            console.log(label, uint256(value));
        }
    }

    function _sendOrder(
        IGmxV2OrderTypes.CreateOrderParams memory order
    ) internal returns (bytes32 key) {
        (, bytes memory resp) = ACCOUNT.exec(
            address(GMX_EXCHANGE_ROUTER),
            abi.encodeWithSelector(
                GMX_EXCHANGE_ROUTER.createOrder.selector,
                order
            )
        );
        key = abi.decode(resp, (bytes32));
    }

    function _createIncreaseOrder(
        address market,
        uint256 sizeUsd,
        uint256 collateralAmount
    ) internal view returns (IGmxV2OrderTypes.CreateOrderParams memory order) {
        order.addresses.receiver = address(ACCOUNT);
        order.addresses.callbackContract = address(ACCOUNT);
        order.addresses.uiFeeReceiver = MANAGER.getUiFeeReceiver();
        order.addresses.market = market;
        order.addresses.initialCollateralToken = address(USDC);
        order.addresses.swapPath = new address[](1);
        order.addresses.swapPath[0] = market;
        order.numbers.sizeDeltaUsd = sizeUsd;
        order.numbers.initialCollateralDeltaAmount = collateralAmount;
        order.numbers.acceptablePrice = 0;
        order.numbers.callbackGasLimit = 1e6;
        order.numbers.minOutputAmount = 0;
        order.orderType = IGmxV2OrderTypes.OrderType.MarketIncrease;
        order.decreasePositionSwapType = IGmxV2OrderTypes
            .DecreasePositionSwapType
            .SwapCollateralTokenToPnlToken;
        order.isLong = false;
        order.shouldUnwrapNativeToken = false;
        order.referralCode = MANAGER.getReferralCode();

        return order;
    }

    function _executeGmxOrder(bytes32 orderKey) internal {
        IGmxV2OrderTypes.Props memory order = _getOrderInfo(orderKey);
        require(order.addresses.market != address(0), "no order exists");
        IOrderHandler.SetPricesParams memory params;

        IGmxV2MarketTypes.Props memory market = _getMarket(
            order.addresses.market
        );

        address shortProvider = MANAGER.gmxV2DataStore().getAddress(
            oracleProviderForTokenKey(market.shortToken)
        );
        address longProvider = MANAGER.gmxV2DataStore().getAddress(
            oracleProviderForTokenKey(market.longToken)
        );
        params.tokens = new address[](2);
        params.tokens[0] = market.shortToken;
        params.tokens[1] = market.longToken;
        params.providers = new address[](2);
        params.providers[0] = shortProvider;
        params.providers[1] = longProvider;
        uint256 priceShort = Pricing.getUnitTokenPriceUSD(
            MANAGER,
            market.shortToken
        ) / 1e6;
        uint256 priceLong = Pricing.getUnitTokenPriceUSD(
            MANAGER,
            market.longToken
        ) * 1e6;
        params.data = new bytes[](2);
        params.data[0] = abi.encode(
            _createFeedReport(market.shortToken, priceShort)
        );
        params.data[1] = abi.encode(
            _createFeedReport(market.longToken, priceLong)
        );
        vm.prank(GMX_ORACLE_SIGNER);
        GMX_ORDER_HANDLER.executeOrder(orderKey, params);
    }

    function _datastore() internal view returns (IGmxV2DataStore) {
        return MANAGER.gmxV2DataStore();
    }

    function _reader() internal view returns (IGmxV2Reader) {
        return MANAGER.gmxV2Reader();
    }

    function _uiFeeReceiver() internal view returns (address) {
        return MANAGER.getUiFeeReceiver();
    }

    function _getOrderInfo(
        bytes32 orderKey
    ) internal view returns (IGmxV2OrderTypes.Props memory) {
        return GMX_READER.getOrder(GMX_DATASTORE, orderKey);
    }

    function _getMarket(
        address market
    ) internal view returns (IGmxV2MarketTypes.Props memory) {
        return GMX_READER.getMarket(_datastore(), market);
    }

    function _getMarketPrices(
        address market
    ) internal view returns (IGmxV2MarketTypes.MarketPrices memory prices) {
        (address shortToken, address longToken) = GmxMarketGetters
            .getMarketTokens(_datastore(), market);
        (uint256 shortTokenPrice, uint256 longTokenPrice) = DeltaConvergenceMath
            .getMarketPrices(MANAGER, shortToken, longToken);
        return
            IGmxV2MarketTypes.MarketPrices(
                IGmxV2PriceTypes.Props(longTokenPrice, longTokenPrice),
                IGmxV2PriceTypes.Props(longTokenPrice, longTokenPrice),
                IGmxV2PriceTypes.Props(shortTokenPrice, shortTokenPrice)
            );
    }

    function _getSwapOutput(
        address market,
        uint256 amount,
        address initialToken
    )
        internal
        view
        returns (uint256, int256, IGmxV2PriceTypes.SwapFees memory)
    {
        return
            _reader().getSwapAmountOut(
                _datastore(),
                _getMarket(market),
                _getMarketPrices(market),
                initialToken,
                amount,
                _uiFeeReceiver()
            );
    }

    function _createFeedReport(
        address asset,
        uint256 assetPrice
    ) internal view returns (IOrderHandler.Report memory report) {
        report.feedId = GMX_DATASTORE.getBytes32(dataStreamIdKey(asset));
        report.validFromTimestamp = uint32(block.timestamp + 1);
        report.observationsTimestamp = uint32(block.timestamp + 1);
        report.expiresAt = uint32(block.timestamp + 100);
        report.nativeFee = 0;
        report.linkFee = 0;
        report.price = int192(uint192(assetPrice));
        report.bid = int192(uint192(assetPrice));
        report.ask = int192(uint192(assetPrice));
    }

    function _getExecutionPrice(
        address market,
        int256 sizeDelta
    ) internal view returns (IGmxV2PriceTypes.ExecutionPriceResult memory) {
        return _getExecutionPrice(market, sizeDelta, 0, 0, false);
    }

    function _getExecutionPrice(
        address market,
        int256 sizeDelta,
        uint256 positionSizeUsd,
        uint256 positionSizeTokens,
        bool isLong
    ) internal view returns (IGmxV2PriceTypes.ExecutionPriceResult memory) {
        return
            _reader().getExecutionPrice(
                _datastore(),
                market,
                _getMarketPrices(market).longTokenPrice,
                positionSizeUsd,
                positionSizeTokens,
                sizeDelta,
                isLong
            );
    }

    // @dev key for data stream feed ID
    // @param token the token to get the key for
    // @return key for data stream feed ID
    function dataStreamIdKey(address token) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(keccak256(abi.encode("DATA_STREAM_ID")), token)
            );
    }

    // @dev key for oracle provider for token
    // @param token the token
    // @return key for oracle provider for token
    function oracleProviderForTokenKey(
        address token
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(abi.encode("ORACLE_PROVIDER_FOR_TOKEN")),
                    token
                )
            );
    }

    function _size(
        address account,
        address market
    ) internal view returns (uint256) {
        return
            DeltaConvergenceMath.getSizeDeltaActualUsd(
                MANAGER,
                account,
                market,
                type(uint256).max
            );
    }

    function _getAccountBalances()
        internal
        view
        returns (uint256 usdcBalance, uint256 wethBalance)
    {
        return (
            USDC.balanceOf(address(ACCOUNT)),
            WETH.balanceOf(address(ACCOUNT))
        );
    }

    function _size() internal view returns (uint256) {
        return _size(address(ACCOUNT), ETH_USD_MARKET);
    }

    function _increase(address market, uint256 collateralAmount) internal {
        (, bytes32 orderKey) = ACCOUNT.executeCreateIncreaseOrder{
            value: 0.01 ether
        }(market, collateralAmount, 0.01 ether);
        _executeGmxOrder(orderKey);
    }

    function _decrease(address market, uint256 sizeDelta) internal {
        (, bytes32 orderKey) = ACCOUNT.executeCreateDecreaseOrder{
            value: 0.01 ether
        }(market, sizeDelta, 0.01 ether);
        _executeGmxOrder(orderKey);
    }

    function _increase(uint256 collateralAmount) internal {
        _increase(ETH_USD_MARKET, collateralAmount);
        _checkPosition();
    }

    function _decrease(uint256 sizeDelta) internal {
        _decrease(ETH_USD_MARKET, sizeDelta);
        _checkPosition();
    }

    function _decreaseExpecting(
        address market,
        uint256 sizeDelta,
        string memory err
    ) internal {
        _expectRevert(err);
        ACCOUNT.executeCreateDecreaseOrder{ value: 0.01 ether }(
            market,
            sizeDelta,
            0.01 ether
        );
    }

    function _decreaseExpecting(uint256 sizeDelta, string memory err) internal {
        _decreaseExpecting(ETH_USD_MARKET, sizeDelta, err);
    }

    // function _getAccountPositionDelta(address account, address market) internal view returns (uint256, bool) {
    //     DeltaConvergenceMath.PositionTokenBreakdown memory b = DeltaConvergenceMath.getAccountMarketDelta(MANAGER, account, market, 0, true);
    // }

    function _getAccountPosition()
        internal
        view
        returns (IGmxV2PositionTypes.PositionInfo memory)
    {
        return
            _getAccountPosition(
                address(ACCOUNT),
                ETH_USD_MARKET,
                address(WETH)
            );
    }

    function _getAccountPosition(
        address account,
        address market,
        address collateralToken
    ) internal view returns (IGmxV2PositionTypes.PositionInfo memory) {
        return
            _reader().getPositionInfo(
                _datastore(),
                GMX_REFERRAL_STORAGE,
                PositionStoreUtils.getPositionKey(
                    account,
                    market,
                    collateralToken,
                    false
                ),
                _getMarketPrices(market),
                0,
                _uiFeeReceiver(),
                true
            );
    }

    function _checkPosition() internal view {
        _checkPosition(address(ACCOUNT), ETH_USD_MARKET, address(WETH));
    }

    function _checkPosition(
        address account,
        address market,
        address /* collateralToken */
    ) internal view {
        DeltaConvergenceMath.PositionTokenBreakdown
            memory b = DeltaConvergenceMath.getAccountMarketDelta(
                MANAGER,
                account,
                market,
                0,
                true
            );
        if (b.tokensShort == 0) return;
        assert(b.leverage > 0.995e18 && b.leverage < 1.005e18);
    }

    function _logAccountPosition() internal view {
        _logPosition(
            _getAccountPosition(address(ACCOUNT), ETH_USD_MARKET, address(WETH))
        );
    }

    function _logAccountPosition(
        address account,
        address market,
        address collateralToken
    ) internal view {
        _logPosition(_getAccountPosition(account, market, collateralToken));
    }

    function _logPosition(
        IGmxV2PositionTypes.PositionInfo memory p
    ) internal view {
        console.log("=========================================");

        console.log("--------------- Addresses ---------------");
        console.log("Market: ", p.position.addresses.market);
        console.log("Account: ", p.position.addresses.account);
        console.log("Collateral Token: ", p.position.addresses.collateralToken);

        console.log("--------------- Numbers ---------------");
        console.log("Size In Usd: ", p.position.numbers.sizeInUsd);
        console.log("Size In Tokens: ", p.position.numbers.sizeInTokens);
        console.log("Collateral Amount: ", p.position.numbers.collateralAmount);
        console.log("Borrowing Factor: ", p.position.numbers.borrowingFactor);
        console.log(
            "Funding Fee Amount Per Size: ",
            p.position.numbers.fundingFeeAmountPerSize
        );
        console.log(
            "Long Token Claimable Funding Amount Per Size: ",
            p.position.numbers.longTokenClaimableFundingAmountPerSize
        );
        console.log(
            "Short Token Claimable Funding Amount Per Size: ",
            p.position.numbers.shortTokenClaimableFundingAmountPerSize
        );
        console.log(
            "Increased at Block: ",
            p.position.numbers.increasedAtBlock
        );
        console.log(
            "Decreased at Block: ",
            p.position.numbers.decreasedAtBlock
        );
        console.log("Increased at Time: ", p.position.numbers.increasedAtTime);
        console.log("Decreased at Time: ", p.position.numbers.decreasedAtTime);

        console.log("--------------- Referral Fees ---------------");
        console.log("Affiliate: ", p.fees.referral.affiliate);
        console.log("Trader: ", p.fees.referral.trader);
        console.log("Total Rebate Factor: ", p.fees.referral.totalRebateFactor);
        console.log(
            "Trader Discount Factor: ",
            p.fees.referral.traderDiscountFactor
        );
        console.log("Total Rebate Amount: ", p.fees.referral.totalRebateAmount);
        console.log(
            "Trader Discount Amount: ",
            p.fees.referral.traderDiscountAmount
        );
        console.log(
            "Affiliate Reward Amount: ",
            p.fees.referral.affiliateRewardAmount
        );

        console.log("--------------- Funding Fees ---------------");
        console.log("Funding Fee Amount: ", p.fees.funding.fundingFeeAmount);
        console.log(
            "Claimable Long Token Amount: ",
            p.fees.funding.claimableLongTokenAmount
        );
        console.log(
            "Claimable Short Token Amount: ",
            p.fees.funding.claimableShortTokenAmount
        );
        console.log(
            "Latest Funding Fee Amount Per Size: ",
            p.fees.funding.latestFundingFeeAmountPerSize
        );
        console.log(
            "Latest Long Token Claimable Funding Amount Per Size: ",
            p.fees.funding.latestLongTokenClaimableFundingAmountPerSize
        );
        console.log(
            "Latest Short Token Claimable Funding Amount Per Size: ",
            p.fees.funding.latestShortTokenClaimableFundingAmountPerSize
        );

        console.log("--------------- Borrowing Fees ---------------");
        console.log("Borrowing Fee Usd: ", p.fees.borrowing.borrowingFeeUsd);
        console.log(
            "Borrowing Fee Amount: ",
            p.fees.borrowing.borrowingFeeAmount
        );
        console.log(
            "Borrowing Fee Receiver Factor: ",
            p.fees.borrowing.borrowingFeeReceiverFactor
        );
        console.log(
            "Borrowing Fee Amount For Fee Receiver: ",
            p.fees.borrowing.borrowingFeeAmountForFeeReceiver
        );

        console.log("--------------- UI Fees ---------------");
        console.log("UI Fee Receiver: ", p.fees.ui.uiFeeReceiver);
        console.log("UI Fee Receiver Factor: ", p.fees.ui.uiFeeReceiverFactor);
        console.log("UI Fee Amount: ", p.fees.ui.uiFeeAmount);

        console.log("--------------- Misc Fees ---------------");
        console.log("Position Fee Factor: ", p.fees.positionFeeFactor);
        console.log("Protocol Fee Amount: ", p.fees.protocolFeeAmount);
        console.log(
            "Position Fee Receiver Factor: ",
            p.fees.positionFeeReceiverFactor
        );
        console.log("Fee Receiver Amount: ", p.fees.feeReceiverAmount);
        console.log("Fee Amount For Pool: ", p.fees.feeAmountForPool);
        console.log(
            "Position Fee Amount For Pool: ",
            p.fees.positionFeeAmountForPool
        );
        console.log("Position Fee Amount: ", p.fees.positionFeeAmount);
        console.log(
            "Total Cost Amount Excluding Funding: ",
            p.fees.totalCostAmountExcludingFunding
        );
        console.log("Total Cost Amount: ", p.fees.totalCostAmount);

        console.log("--------------- Execution Price Result ---------------");
        _logInt256("Price Impact Usd: ", p.executionPriceResult.priceImpactUsd);
        console.log(
            "Price Impact Diff Usd: ",
            p.executionPriceResult.priceImpactDiffUsd
        );
        console.log("Execution Price: ", p.executionPriceResult.executionPrice);

        console.log("--------------- Position PnL ---------------");
        _logInt256("Base PnL Usd: ", p.basePnlUsd);
        _logInt256("Uncapped Base PnL Usd: ", p.uncappedBasePnlUsd);
        _logInt256("Pnl After Price Impact: ", p.pnlAfterPriceImpactUsd);
    }

    // GMX HACKS

    // Modify Position Borrowing Fees

    function _setPositionBorrowingFees(
        address account,
        address market,
        address collateralToken
    ) internal {}

    // @dev get the cumulative borrowing factor for a market
    // @param dataStore DataStore
    // @param market the market to check
    // @param isLong whether to check the long or short side
    // @return the cumulative borrowing factor for a market
    // function getCumulativeBorrowingFactor(DataStore dataStore, address market, bool isLong) internal view returns (uint256) {
    //     return dataStore.getUint(Keys.cumulativeBorrowingFactorKey(market, isLong));
    // }
    // @dev get the borrowing factor for a market
    // @param dataStore DataStore
    // @param market the market to check
    // @param isLong whether to check the long or short side
    // @return the borrowing factor for a market
    // function getBorrowingFactor(DataStore dataStore, address market, bool isLong) internal view returns (uint256) {
    //     return dataStore.getUint(Keys.borrowingFactorKey(market, isLong));
    // }

    // @dev get the borrowing fees for a position, assumes that cumulativeBorrowingFactor
    // has already been updated to the latest value
    // @param dataStore DataStore
    // @param position Position.Props
    // @return the borrowing fees for a position
    // function getBorrowingFees(DataStore dataStore, Position.Props memory position) internal view returns (uint256) {
    //     uint256 cumulativeBorrowingFactor = getCumulativeBorrowingFactor(dataStore, position.market(), position.isLong());
    //     if (position.borrowingFactor() > cumulativeBorrowingFactor) {
    //         revert Errors.UnexpectedBorrowingFactor(position.borrowingFactor(), cumulativeBorrowingFactor);
    //     }
    //     uint256 diffFactor = cumulativeBorrowingFactor - position.borrowingFactor();
    //     return Precision.applyFactor(position.sizeInUsd(), diffFactor);
    // }
}

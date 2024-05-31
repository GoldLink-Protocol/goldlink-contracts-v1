// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import { MockAccountSetup } from "./MockAccountSetup.sol";
import { GmxFrfStrategyMetadata } from "../GmxFrfStrategyMetadata.sol";
import {IGmxV2OrderTypes} from "../../../../contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import {IGmxV2MarketTypes} from "../../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2MarketTypes.sol";
import { IOrderHandler } from "./IOrderHandler.sol";
import {
    GmxMarketGetters
} from "../../../../contracts/strategies/gmxFrf/libraries/GmxMarketGetters.sol";


abstract contract MockAccountGmxHelpers is MockAccountSetup {

    address ORACLE_SIGNER = 0xC539cB358a58aC67185BaAD4d5E3f7fCfc903700;


    function _sendOrder(IGmxV2OrderTypes.CreateOrderParams memory order) internal returns (bytes32 key) {
        (, bytes memory resp) = ACCOUNT.exec(address(GmxFrfStrategyMetadata.GMX_V2_EXCHANGE_ROUTER), abi.encodeWithSelector(GmxFrfStrategyMetadata.GMX_V2_EXCHANGE_ROUTER.createOrder.selector, order));
        key = abi.decode(resp, (bytes32));
    }

    function _createIncreaseOrder(address market, uint256 sizeUsd, uint256 collateralAmount) internal returns (IGmxV2OrderTypes.CreateOrderParams memory order) {
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


        IGmxV2MarketTypes.Props memory market = _getMarket(order.addresses.market);

        params.realtimeFeedTokens = new address[](2);
        params.realtimeFeedTokens[0] = market.shortToken;
        params.realtimeFeedTokens[1] = market.longToken;
        params.realtimeFeedData = new bytes[](2);
        (uint256 priceShort,) = MANAGER.getAssetPrice(market.shortToken);
        (uint256 priceLong,) = MANAGER.getAssetPrice(market.longToken);

        params.realtimeFeedData[0] = abi.encode(_createRealTimeFeedReport(market.shortToken, priceShort));
        params.realtimeFeedData[1] = abi.encode(_createRealTimeFeedReport(market.longToken, priceLong));
        vm.prank(ORACLE_SIGNER);
        IOrderHandler(0x352f684ab9e97a6321a13CF03A61316B681D9fD2).executeOrder(orderKey, params);
    }


    function _getOrderInfo(bytes32 orderKey) internal returns (IGmxV2OrderTypes.Props memory) {
       return GmxFrfStrategyMetadata.GMX_V2_READER.getOrder(GmxFrfStrategyMetadata.GMX_V2_DATASTORE, orderKey);
    }

    function _getMarket(address market) internal returns (IGmxV2MarketTypes.Props memory) {
        return GmxFrfStrategyMetadata.GMX_V2_READER.getMarket(GmxFrfStrategyMetadata.GMX_V2_DATASTORE, market);
    }

    function _createRealTimeFeedReport(address asset, uint256 assetPrice) internal returns (IOrderHandler.RealtimeFeedReport memory report) {
        report.feedId = GmxFrfStrategyMetadata.GMX_V2_DATASTORE.getBytes32(realtimeFeedIdKey(asset));
        report.observationsTimestamp = uint32(block.timestamp - 20);
        report.median = int192(uint192(assetPrice));
        report.bid = int192(uint192(assetPrice));
        report.ask = int192(uint192(assetPrice));
        report.blocknumberUpperBound = uint64(block.number);
        report.upperBlockhash = ARBSYS.arbBlockHash(report.blocknumberUpperBound);
        report.blocknumberLowerBound = uint64(block.number - 20);
        report.currentBlockTimestamp = uint64(block.timestamp);
    }

    function realtimeFeedIdKey(address token) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            keccak256(abi.encode("REALTIME_FEED_ID")),
            token
        ));
    }
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {
    IChainlinkAggregatorV3
} from "../../../../contracts/adapters/chainlink/interfaces/external/IChainlinkAggregatorV3.sol";

import {
    OracleAssetRegistry
} from "../../../../contracts/adapters/chainlink/OracleAssetRegistry.sol";
import {
    ChainlinkAggregatorMock
} from "../../../mocks/ChainlinkAggregatorMock.sol";
import {
    Pricing
} from "../../../../contracts/strategies/gmxFrf/libraries/Pricing.sol";
import { TokenDeployer } from "../../../TokenDeployer.sol";
import {
    IGmxFrfStrategyManager
} from "../../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";

contract PricingTest is OracleAssetRegistry, Test, TokenDeployer {
    address public account;

    IGmxFrfStrategyManager oracle = IGmxFrfStrategyManager(address(this));

    ChainlinkAggregatorMock public usdcOracleMock;
    ChainlinkAggregatorMock public wethOracleMock;
    ChainlinkAggregatorMock public wbtcOracleMock;
    ChainlinkAggregatorMock public arbOracleMock;

    function setUp() public {
        usdcOracleMock = new ChainlinkAggregatorMock(8, 1e8);
        wethOracleMock = new ChainlinkAggregatorMock(12, 2e15);
        wbtcOracleMock = new ChainlinkAggregatorMock(8, 4e12);
        arbOracleMock = new ChainlinkAggregatorMock(18, 1e18);

        _setAssetOracle(address(usdc), usdcOracleMock, 1 days);
        _setAssetOracle(address(weth), wethOracleMock, 20 minutes);
        _setAssetOracle(address(wbtc), wbtcOracleMock, 10 minutes);
        _setAssetOracle(address(arb), arbOracleMock, 10 minutes);
    }

    // ============ GetAssetPriceUSD Tests ============

    function testGetAssetPriceAnswerIsZero() public {
        usdcOracleMock.updateAnswer(0);
        vm.expectRevert("OracleRegistry: Invalid oracle price.");
        Pricing.getUnitTokenPriceUSD(oracle, address(usdc));
    }

    function testGetAssetPriceAnswerIsNegative() public {
        usdcOracleMock.updateAnswer(-300000);
        vm.expectRevert("OracleRegistry: Invalid oracle price.");
        Pricing.getUnitTokenPriceUSD(oracle, address(usdc));
    }

    function testGetAssetPriceOracleIsStale() public {
        usdcOracleMock.updateAnswer(1e8);
        usdcOracleMock.updateRoundData(1, 1e8, 0, 0);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(
            "OracleRegistry: Last update timestamp exceeds valid timestamp range."
        );
        Pricing.getUnitTokenPriceUSD(oracle, address(usdc));
    }

    function testGetAssetPriceUSD() public {
        usdcOracleMock.updateAnswer(1.1e8);
        uint256 price = Pricing.getUnitTokenPriceUSD(oracle, address(usdc));
        assertEq(price, 1.1e24);
    }

    function testGetAssetPriceUSDPriceIsSmall() public {
        arbOracleMock.updateAnswer(1.8434e15); // 0.0018
        uint256 price = Pricing.getUnitTokenPriceUSD(oracle, address(arb));
        assertEq(price, 1.8434e9);
    }
}

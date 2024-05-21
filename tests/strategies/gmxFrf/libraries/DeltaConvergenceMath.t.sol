// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {
    DeltaConvergenceMath
} from "../../../../contracts/strategies/gmxFrf/libraries/DeltaConvergenceMath.sol";

import {
    IGmxV2PositionTypes
} from "../../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";

contract DeltaConvergenceMathTest is Test {
    // ============ Setup ============

    function setUp() public {
        // Empty.
    }

    // ============ Get Increase Size Delta Tests ============

    function testGetIncreaseSizeDeltaLessCollateralAfter() public {
        assertEq(DeltaConvergenceMath.getIncreaseSizeDelta(1e18, 1e17, 1e6), 0);
    }

    function testGetIncreaseSizeDeltaEqualCollateralAfter() public {
        assertEq(DeltaConvergenceMath.getIncreaseSizeDelta(1e18, 1e18, 1e6), 0);
    }

    function testGetIncreaseSizeDeltaGreaterCollateralAfter() public {
        assertEq(
            DeltaConvergenceMath.getIncreaseSizeDelta(1e17, 1e18, 1e6),
            9e23
        );
    }

    // ============ GetPositionValueUSD Tests =============

    function testGetPositionValueUSDBasic() public pure {
        IGmxV2PositionTypes.PositionInfo memory positionInfo;

        positionInfo.fees.funding.claimableShortTokenAmount = 12e6; // 12 USDC
        positionInfo.fees.funding.claimableLongTokenAmount = 0.08e18; // 0.08 ETH
        positionInfo.position.numbers.collateralAmount = 1e18; // 1 ETH
        positionInfo.fees.totalCostAmount = 0.005e18; // 0.005 ETH
        positionInfo.pnlAfterPriceImpactUsd = -5e30; // - 5 USD

        uint256 shortTokenPrice = 1.001e24; // $1.001
        uint256 longTokenPrice = 2448e12; // $2448

        uint256 valueUSD = DeltaConvergenceMath.getPositionValueUSD(
            positionInfo,
            shortTokenPrice,
            longTokenPrice
        );

        // 12 * 1.0001 + (1 + 0.08 - 0.005) * 2448 - 5 = 2638.612

        assert(valueUSD == 2638.612e30);
    }

    function testGetValueUSDZeroFundingFees() public pure {
        IGmxV2PositionTypes.PositionInfo memory positionInfo;

        positionInfo.position.numbers.collateralAmount = 1e18; // 1 ETH
        positionInfo.fees.totalCostAmount = 0.005e18; // 0.005 ETH
        positionInfo.pnlAfterPriceImpactUsd = -5e30; // - 5 USD

        uint256 shortTokenPrice = 1.001e24; // $1.001
        uint256 longTokenPrice = 2448e12; // $2448

        uint256 valueUSD = DeltaConvergenceMath.getPositionValueUSD(
            positionInfo,
            shortTokenPrice,
            longTokenPrice
        );

        // (1 - 0.005) * 2448 - 5 = 2,430.76
        assert(valueUSD == 2430.76e30);
    }

    function testGetValueUSDSignificantPositivePnL() public pure {
        IGmxV2PositionTypes.PositionInfo memory positionInfo;

        positionInfo.fees.funding.claimableShortTokenAmount = 12e6; // 12 USDC
        positionInfo.fees.funding.claimableLongTokenAmount = 0.08e18; // 0.08 ETH
        positionInfo.position.numbers.collateralAmount = 1e18; // 1 ETH
        positionInfo.fees.totalCostAmount = 0.005e18; // 0.005 ETH
        positionInfo.pnlAfterPriceImpactUsd = 5000e30; // 5000 USD

        uint256 shortTokenPrice = 1.001e24; // $1.001
        uint256 longTokenPrice = 2448e12; // $2448

        uint256 valueUSD = DeltaConvergenceMath.getPositionValueUSD(
            positionInfo,
            shortTokenPrice,
            longTokenPrice
        );

        // 12 * 1.0001 + (1 + 0.08 - 0.005) * 2448 + 5000 = 2638.612

        assert(valueUSD == 7643.612e30);
    }

    // ============ Get Delta Proportion Tests ============

    function testGetDeltaProportionShort() public {
        (uint256 proportion, bool isShort) = DeltaConvergenceMath
            .getDeltaProportion(1e18, 5e17);
        assertEq(proportion, 2e18);
        assertTrue(isShort);
    }

    function testGetDeltaProportionLong() public {
        (uint256 proportion, bool isShort) = DeltaConvergenceMath
            .getDeltaProportion(5e17, 7.5e17);
        assertEq(proportion, 1.5e18);
        assertFalse(isShort);
    }

    function testGetDeltaProportionEqual() public {
        (uint256 proportion, bool isShort) = DeltaConvergenceMath
            .getDeltaProportion(1e18, 1e18);
        assertEq(proportion, 1e18);
        assertFalse(isShort);
    }
}

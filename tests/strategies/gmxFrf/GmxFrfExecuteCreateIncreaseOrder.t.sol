// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import {
    IMarketConfiguration
} from "@contracts/strategies/gmxFrf/interfaces/IMarketConfiguration.sol";
import {
    GmxFrfStrategyAccount
} from "@contracts/strategies/gmxFrf/GmxFrfStrategyAccount.sol";
import { MockAccountHelpers } from "./MockDeployment/MockAccountHelpers.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import {
    IGmxV2OrderTypes
} from "@contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import { Pricing } from "@contracts/strategies/gmxFrf/libraries/Pricing.sol";
import { Errors } from "@contracts/libraries/Errors.sol";
import { PercentMath } from "@contracts/libraries/PercentMath.sol";

/**
 * @title GmxFrfExecuteCreateIncreaseOrderTest
 * @author Trevor Judice
 *
 * @dev ExecuteCreateIncreaseOrder Invariants:
 * 1) Account value should be equivalent before and after an order is created. The changes to the account's value are only reflected after the order has been executed.
 * 2) The imbalance (tokensLong - tokensShort) for a given market should strictly decrease, assuming prices remain constant. In the test environment, the price of assets is the same when creating and executing an order.
 * However, in a production environemnt, it is possible the price of an asset changes in between order creation and keeper execution. Therefore, this invariant only applies assuming prices remain constant. Shifts in price should not effect the
 * security of the protocol, and there is no way of preventing an order from being executed once the order has been placed unless it is cancelled. Note: This does not imply the `deltaProportion` of the position is strictly decreasing. This is because tokens
 * that do not comprise the `position`, i.e. Account Token Balance, Unsettled Funding Fees and Unclaimed Funding Fees are not effected by increase/decrease orders (other than unsettled moving to unclaimed). For example, an account has a position
 * on GMX with 1 WETH long and 1 WETH short and an account balance of 0.1 WETH. The current imbalance for this position is 1.1 - 1 = 0.1 WETH. Closing the position results in the account's imbalance for the WETH-USDC market to remain the same, as it is now calculated
 * as 0.1 - 0 = 0.1 . However, the `deltaProportion` has increased (and is now technically infinitely `long`). While not prohibited by the protocol, a frontend should warn the user if closing their position would make it possible to rebalance their account, as in this example.
 * 3) The output amount of the swap should abide by the `minSwapOutput` configuration present in the manager. This is enforced by GMX.
 * 4) Increase orders should target a leverage of 1.0, not a delta of 1.0. This implies that the leverage before an increase order is executed should be further from 1 than the leverage of the position after the order is executed.
 */
contract GmxFrfExecuteCreateIncreaseOrderTest is MockAccountHelpers {
    using PercentMath for uint256;

    // ============ ExecuteCreateIncreaseOrder ============

    // Modifier Checks
    function testExecuteCreateIncreaseOrderNotOwner() public {
        payable(address(10)).transfer(0.01 ether);
        vm.prank(address(10));
        _expectRevert(Errors.STRATEGY_ACCOUNT_SENDER_IS_NOT_OWNER);
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e8,
            0.01 ether
        );
    }

    function testExecuteCreateIncreaseOrderLiquidationActive() public {
        _sendFromAccount(address(USDC), address(this), 40000000000);
        ACCOUNT.executeInitiateLiquidation();
        _expectRevert(
            Errors.STRATEGY_ACCOUNT_CANNOT_CALL_WHILE_LIQUIDATION_ACTIVE
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e8,
            0.01 ether
        );
    }

    function testExecuteCreateIncreaseOrderLoanNotActive() public {
        address newAccount = BANK.executeOpenAccount(address(this));
        _expectRevert(Errors.STRATEGY_ACCOUNT_ACCOUNT_HAS_NO_LOAN);
        GmxFrfStrategyAccount(payable(newAccount)).executeCreateIncreaseOrder{
            value: 0.01 ether
        }(ETH_USD_MARKET, 1e8, 0.01 ether);
    }

    function testExecuteCreateIncreaseOrderMarketNotApproved() public {
        _expectRevert(
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            address(1),
            1e8,
            0.01 ether
        );
    }

    function testExecuteIncreaseOrderCannotPayFee() public {
        _expectRevert(
            GmxFrfStrategyErrors.MSG_VALUE_LESS_THAN_PROVIDED_EXECUTION_FEE
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.00000001 ether }(
            ETH_USD_MARKET,
            1e8,
            0.01 ether
        );
    }

    // function testExecuteCreateIncreaseOrderOrdersNotEnabled() public {
    //     // TODO: Need to modify config.
    //     revert("not implemented");
    // }

    function testExecuteCreateIncreaseOrderHasPendingOrders() public {
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e8,
            0.01 ether
        );
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_VALIDATION_MARKET_HAS_PENDING_ORDERS
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e8,
            0.01 ether
        );
    }

    function testExecuteCreateIncreaseOrderCollateralAmountGreaterThanBalance()
        public
    {
        _sendFromAccount(address(USDC), address(this), 35000000000);
        _expectRevert(
            GmxFrfStrategyErrors
                .ORDER_VALIDATION_INITIAL_COLLATERAL_BALANCE_IS_TOO_LOW
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            55000000000,
            0.01 ether
        );
    }

    function testExecuteCreateIncreaseOrderSwapSlippageTooHigh() public {
        ETH_USD_ORACLE_MOCK.updateAnswer(200000e8);
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_VALIDATION_SWAP_SLIPPAGE_IS_TOO_HGIH
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            2e10,
            0.01 ether
        );
    }

    function testExecuteCreateIncreaseOrderOrderSizeTooSmall() public {
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_VALIDATION_ORDER_SIZE_IS_TOO_SMALL
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            0,
            0.01 ether
        );
    }

    function testExecuteCreateIncreaseOrderOrderSizeTooLarge() public {
        USDC.transfer(address(ACCOUNT), 1e11);
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_VALIDATION_ORDER_SIZE_IS_TOO_LARGE
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1.2e11,
            0.01 ether
        );
    }

    function testExecuteCreateIncreaseOrderPositionSizeTooSmall() public {
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_VALIDATION_POSITION_SIZE_IS_TOO_SMALL
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            1e3,
            0.01 ether
        );
    }

    function testExecuteCreateIncreaseOrderPositionSizeTooLarge() public {
        USDC.transfer(address(ACCOUNT), 890000000000);
        (, bytes32 orderKey) = ACCOUNT.executeCreateIncreaseOrder{
            value: 0.01 ether
        }(ETH_USD_MARKET, 45000e6, 0.01 ether);
        _executeGmxOrder(orderKey);
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_VALIDATION_POSITION_SIZE_IS_TOO_LARGE
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
            ETH_USD_MARKET,
            45000e6,
            0.01 ether
        );
    }

    function testExecuteCreateIncreaseOrderInvalidExecutionFeeProvided()
        public
    {
        _expectRevert(
            GmxFrfStrategyErrors
                .ORDER_VALIDATION_PROVIDED_EXECUTION_FEE_IS_TOO_LOW
        );
        ACCOUNT.executeCreateIncreaseOrder{ value: 0.00000001 ether }(
            ETH_USD_MARKET,
            1e8,
            0.00000001 ether
        );
    }

    // Non-Reverting tets
    function testExecuteCreateIncreaseOrderNoPositionActive() public {
        uint256 usdcBefore = USDC.balanceOf(address(ACCOUNT));
        uint256 currValue = ACCOUNT.getAccountValue();
        (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        ) = ACCOUNT.executeCreateIncreaseOrder{ value: 0.01 ether }(
                ETH_USD_MARKET,
                1e8,
                0.01 ether
            );
        assert(ACCOUNT.getAccountValue() == currValue); // Account value should not change during increase orders.
        assert(USDC.balanceOf(address(ACCOUNT)) == usdcBefore - 1e8);
        _checkOrderAddresses(order.addresses, ETH_USD_MARKET, address(USDC));
        (uint256 out, , ) = _getSwapOutput(ETH_USD_MARKET, 1e8, address(USDC));
        uint256 px = Pricing.getUnitTokenPriceUSD(MANAGER, address(WETH));
        uint256 expectedSizeDelta = out *
            _getExecutionPrice(ETH_USD_MARKET, int256(px * out)).executionPrice;
        assert(order.numbers.sizeDeltaUsd == expectedSizeDelta);
        assert(order.numbers.initialCollateralDeltaAmount == 1e8);
        uint256 wethPrice = Pricing.getUnitTokenPriceUSD(
            MANAGER,
            address(WETH)
        );
        IMarketConfiguration.MarketConfiguration memory config = MANAGER
            .getMarketConfiguration(ETH_USD_MARKET);
        uint256 expectedPrice = wethPrice -
            wethPrice.percentToFraction(
                config.orderPricingParameters.maxPositionSlippagePercent
            );
        assert(order.numbers.acceptablePrice == expectedPrice);
        assert(order.numbers.triggerPrice == 0);
        assert(order.numbers.executionFee == 0.01 ether);
        assert(
            order.numbers.callbackGasLimit ==
                config.sharedOrderParameters.callbackGasLimit
        );
        uint256 usdcPrice = Pricing.getUnitTokenPriceUSD(
            MANAGER,
            address(USDC)
        );
        uint256 outputMarkedToMarket = Math.mulDiv(1e8, usdcPrice, wethPrice);
        uint256 minOut = outputMarkedToMarket -
            outputMarkedToMarket.percentToFraction(
                config.orderPricingParameters.maxSwapSlippagePercent
            );
        assert(order.numbers.minOutputAmount == minOut);
        uint256 balanceBefore = address(this).balance;
        _executeGmxOrder(orderKey);
        assert(balanceBefore != address(this).balance); // Make sure that the execution fee is properly being forwarded back to the caller.

        uint256 delta = _getAccountPositionDeltaNumber(
            address(ACCOUNT),
            ETH_USD_MARKET
        );
        assert(delta <= 1.005e18);
    }

    function testExecuteCreateIncreaseOrderHasBalancedPosition() public {
        _increase(1e8);
        _increase(1e8);
        uint256 delta = _getAccountPositionDeltaNumber(
            address(ACCOUNT),
            ETH_USD_MARKET
        );
        assert(delta <= 1.005e18);
        _checkPosition(address(ACCOUNT), ETH_USD_MARKET, address(WETH));
    }

    function testExecuteCreateIncreaseOrderHasPositionDeltaPositiveUnsettled()
        public
    {
        _increase(1e8);

        vm.warp(block.timestamp + 20000000);
        USDC_USD_ORACLE_MOCK.poke();
        ETH_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();
        _increase(1e8);
        _checkPosition(address(ACCOUNT), ETH_USD_MARKET, address(WETH));
    }

    function testExecuteCreateIncreaseOrderHasPositionDeltaPositiveUnclaimed()
        public
    {
        _increase(2e10);

        vm.warp(block.timestamp + 20000000);
        USDC_USD_ORACLE_MOCK.poke();
        ETH_USD_ORACLE_MOCK.poke();
        ARB_USD_ORACLE_MOCK.poke();

        _decrease(2);
        _increase(2e10);
        // Check to make sure leverage is sufficient.
        _checkPosition(address(ACCOUNT), ETH_USD_MARKET, address(WETH));
    }

    function testExecuteCreateIncreaseOrderPnlIsVeryNegative() public {
        _increase(2e10);

        // Set oracle price of ETH to 10000. This would imply the short position is very negative.
        ETH_USD_ORACLE_MOCK.updateAnswer(1e12);
        _increase(2e10);
        // Leverage should remain.
        _checkPosition(address(ACCOUNT), ETH_USD_MARKET, address(WETH));
    }

    function testExecuteCreateIncreaseOrderPnlIsVeryPositive() public {
        _increase(1e10);

        ETH_USD_ORACLE_MOCK.updateAnswer(1.5e11);

        _increase(2e10);

        // Check to make sure leverage is sufficient.
        _checkPosition(address(ACCOUNT), ETH_USD_MARKET, address(WETH));
    }

    function testExecuteCreateIncreaseOrderGmx() public {
        _increase(GMX_USD_MARKET, 1e10);
        // Check to make sure leverage is sufficient.
        console.log(ACCOUNT.getAccountValue());
        _decrease(GMX_USD_MARKET, _size(address(ACCOUNT), GMX_USD_MARKET));
        console.log(ACCOUNT.getAccountValue());
    }

    receive() external payable {}
}

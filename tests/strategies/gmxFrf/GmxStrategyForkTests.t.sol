// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { TestConstants } from "../../testLibraries/TestConstants.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    IGmxV2MarketTypes
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2MarketTypes.sol";
import {
    IChainlinkAdapter
} from "../../../contracts/adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import { TokenDeployer } from "../../TokenDeployer.sol";
import {
    ChainlinkAggregatorMock
} from "../../mocks/ChainlinkAggregatorMock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TestUtilities } from "../../testLibraries/TestUtilities.sol";
import {
    GmxFrfStrategyDeployer
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyDeployer.sol";
import {
    GmxFrfStrategyManager
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyManager.sol";
import {
    IDeploymentConfiguration
} from "../../../contracts/strategies/gmxFrf/interfaces/IDeploymentConfiguration.sol";
import {
    IMarketConfiguration
} from "../../../contracts/strategies/gmxFrf/interfaces/IMarketConfiguration.sol";
import {
    GmxFrfStrategyAccount
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyAccount.sol";
import {
    IGmxV2ExchangeRouter
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2ExchangeRouter.sol";
import {
    IGmxV2Reader
} from "../../../contracts/lib/gmx/interfaces/external/IGmxV2Reader.sol";
import {
    IGmxV2DataStore
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2RoleStore
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2RoleStore.sol";
import {
    IGmxV2PositionTypes
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";
import {
    IGmxV2OrderTypes
} from "../../../contracts/lib/gmx/interfaces/external/IGmxV2OrderTypes.sol";
import {
    IGmxFrfStrategyDeployer
} from "../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyDeployer.sol";
import {
    IGmxFrfStrategyManager
} from "../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";
import {
    IGmxFrfStrategyAccount
} from "../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyAccount.sol";
import { IStrategyBank } from "../../../contracts/interfaces/IStrategyBank.sol";
import {
    IStrategyController
} from "../../../contracts/interfaces/IStrategyController.sol";
import { GmxFrfStrategyMetadata } from "./GmxFrfStrategyMetadata.sol";
import {
    Pricing
} from "../../../contracts/strategies/gmxFrf/libraries/Pricing.sol";
import {
    DeltaConvergenceMath
} from "../../../contracts/strategies/gmxFrf/libraries/DeltaConvergenceMath.sol";
import { MockArbSys } from "../../mocks/MockArbSys.sol";
import {
    IGmxV2PriceTypes
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2PriceTypes.sol";
import {
    OrderStoreUtils
} from "../../../contracts/lib/gmx/order/OrderStoreUtils.sol";
import {
    GmxStorageGetters
} from "../../../contracts/strategies/gmxFrf/libraries/GmxStorageGetters.sol";

import {
    PositionStoreUtils
} from "../../../contracts/lib/gmx/position/PositionStoreUtils.sol";
import {
    GmxMarketGetters
} from "../../../contracts/strategies/gmxFrf/libraries/GmxMarketGetters.sol";
import { StrategyReserve } from "../../../contracts/core/StrategyReserve.sol";
import { StrategyBank } from "../../../contracts/core/StrategyBank.sol";
import {
    IStrategyReserve
} from "../../../contracts/interfaces/IStrategyReserve.sol";
import {
    IStrategyAccountDeployer
} from "../../../contracts/interfaces/IStrategyAccountDeployer.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import { ProtocolDeployer } from "../../ProtocolDeployer.sol";
import { StrategyDeployerHelper } from "./StrategyDeployerHelper.sol";

import {
    DeltaConvergenceMath
} from "../../../contracts/strategies/gmxFrf/libraries/DeltaConvergenceMath.sol";

contract GmxStrategyForkTests is
    StrategyDeployerHelper,
    ProtocolDeployer,
    IStrategyAccountDeployer
{
    uint256 constant VALID_ORACLE_PRICE_DURATION = 10 minutes;
    uint256 constant STABLE_ASSET_VALID_ORACLE_PRICE_DURATION = 1e6;
    bool receivedExcessExecutionFee = false;

    IGmxFrfStrategyDeployer public accountDeployer;
    IGmxFrfStrategyManager public manager;

    IGmxFrfStrategyAccount public account;

    IGmxFrfStrategyAccount public etched;

    IChainlinkAdapter public oracleRegistry;

    StrategyReserve public reserve;
    IStrategyBank public bank;

    bytes32 positionNow;

    int256 liquidatedAssetsOffset = 0;

    address strategyAccountFixture;

    /**
     * @dev Returns mock account. Conforms to IStrategyAccountDeployer interface.
     */
    function deployAccount(
        address owner,
        IStrategyController strategyController
    ) external override returns (address) {
        if (strategyAccountFixture == address(0)) {
            return accountDeployer.deployAccount(owner, strategyController);
        }
        return strategyAccountFixture;
    }

    constructor() ProtocolDeployer(false) {}

    function setUp() public {
        // Since foundry for some reason doesn't handle predeploys (even though they say they do);
        MockArbSys arbSys = new MockArbSys();
        vm.etch(
            address(0x0000000000000000000000000000000000000064),
            address(arbSys).code
        );

        (
            IStrategyReserve strategyReserve,
            IStrategyBank strategyBank,
            IStrategyController strategyController
        ) = _createStrategy(
                GmxFrfStrategyMetadata.USDC,
                TestUtilities.defaultBankParameters(this),
                TestConstants.defaultReserveParameters()
            );

        reserve = StrategyReserve(address(strategyReserve));
        bank = StrategyBank(address(strategyBank));

        IChainlinkAdapter.OracleConfiguration memory oc = IChainlinkAdapter
            .OracleConfiguration(
                STABLE_ASSET_VALID_ORACLE_PRICE_DURATION,
                GmxFrfStrategyMetadata.USDC_USD_ORACLE
            );

        (manager, ) = deployManager(oc);
        (accountDeployer, ) = deployAccountDeployer(manager);

        GmxFrfStrategyMetadata.GMX_V2_EXCHANGE_ROUTER.setUiFeeFactor(2e26); // 0.02%.

        account = IGmxFrfStrategyAccount(
            strategyBank.executeOpenAccount(address(this))
        );

        etched = _etchToPositionHolder(
            0x7bDeA133D396F78A05999782f7a56Fa292b6FAc5
        );

        etched.initialize(address(this), strategyController);

        // This will be the account address returned when calling deployAccount().
        strategyAccountFixture = address(etched);

        bank.executeOpenAccount(address(this));

        manager.setMarket(
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            IChainlinkAdapter.OracleConfiguration(
                VALID_ORACLE_PRICE_DURATION,
                GmxFrfStrategyMetadata.ETH_USD_ORACLE
            ),
            _defaultPricingParams(),
            _defaultPositionParameters(),
            _defaultUnwindParameters(),
            2e16
        );

        manager.setMarket(
            GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
            IChainlinkAdapter.OracleConfiguration(
                VALID_ORACLE_PRICE_DURATION,
                GmxFrfStrategyMetadata.ARB_USD_ORACLE
            ),
            _defaultPricingParams(),
            _defaultPositionParameters(),
            _defaultUnwindParameters(),
            2e16
        );

        manager.setMarket(
            GmxFrfStrategyMetadata.GMX_V2_WBTC_USDC_MARKET,
            IChainlinkAdapter.OracleConfiguration(
                VALID_ORACLE_PRICE_DURATION,
                GmxFrfStrategyMetadata.BTC_USD_ORACLE
            ),
            _defaultPricingParams(),
            _defaultPositionParameters(),
            _defaultUnwindParameters(),
            2e16
        );

        vm.deal(address(this), 20 ether);
        GmxFrfStrategyMetadata.WETH.deposit{ value: 10 ether }();
        vm.prank(0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D);
        GmxFrfStrategyMetadata.USDC.transfer(address(address(this)), 1e13);
        vm.prank(0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D);
        GmxFrfStrategyMetadata.ARB.transfer(address(address(this)), 1e24);
        vm.prank(0x69eC552BE56E6505703f0C861c40039e5702037A);
        GmxFrfStrategyMetadata.WBTC.transfer(address(address(this)), 1e9);

        GmxFrfStrategyMetadata.USDC.approve(
            address(reserve),
            type(uint256).max
        );
        strategyReserve.deposit(1e11, address(this));
        GmxFrfStrategyMetadata.USDC.approve(address(bank), type(uint256).max);
        account.executeAddCollateral(9e11);
        account.executeBorrow(1e10);

        GmxFrfStrategyMetadata.USDC.approve(address(bank), type(uint256).max);
        etched.executeAddCollateral(9e11);
        etched.executeBorrow(1e10);
    }

    function liquidationSwapCallback(uint256, uint256 expectedUsdc) external {
        if (liquidatedAssetsOffset < 0) {
            GmxFrfStrategyMetadata.USDC.transfer(
                msg.sender,
                expectedUsdc - uint256(-liquidatedAssetsOffset)
            );
        } else {
            GmxFrfStrategyMetadata.USDC.transfer(
                msg.sender,
                expectedUsdc + uint256(liquidatedAssetsOffset)
            );
        }
    }

    // ==================== Multicall Tests ====================

    function testMultiCallSpendMoreThanValue() public {
        vm.deal(address(etched), 10 ether);

        GmxFrfStrategyMetadata.USDC.transfer(address(etched), 1e9);

        bytes[] memory calls = new bytes[](2);

        calls[0] = abi.encodeWithSelector(
            IGmxFrfStrategyAccount.executeCreateIncreaseOrder.selector,
            GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
            1e8,
            1 ether
        );

        calls[1] = abi.encodeWithSelector(
            IGmxFrfStrategyAccount.executeCreateIncreaseOrder.selector,
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            1e8,
            1 ether
        );

        _expectRevert(
            GmxFrfStrategyErrors
                .TOO_MUCH_NATIVE_TOKEN_SPENT_IN_MULTICALL_EXECUTION
        );

        etched.multicall{ value: 1 ether }(calls);
    }

    function testMultiCallOk() public {
        vm.deal(address(etched), 10 ether);

        GmxFrfStrategyMetadata.USDC.transfer(address(etched), 1e9);

        bytes[] memory calls = new bytes[](2);

        calls[0] = abi.encodeWithSelector(
            bytes4(
                keccak256("executeCreateIncreaseOrder(address,uint256,uint256)")
            ),
            GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
            1e8,
            1 ether
        );

        calls[1] = abi.encodeWithSelector(
            bytes4(
                keccak256("executeCreateIncreaseOrder(address,uint256,uint256)")
            ),
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            1e8,
            1 ether
        );

        etched.multicall{ value: 2 ether }(calls);
    }

    // ==================== Add Market Tests ====================

    function testSetMarketDoesNotExist() public {
        _expectRevert(
            GmxFrfStrategyErrors
                .GMX_FRF_STRATEGY_MANAGER_SHORT_TOKEN_MUST_BE_USDC
        );
        manager.setMarket(
            address(1),
            IChainlinkAdapter.OracleConfiguration(
                1e6,
                GmxFrfStrategyMetadata.USDC_USD_ORACLE
            ),
            _defaultPricingParams(),
            _defaultPositionParameters(),
            _defaultUnwindParameters(),
            2e16
        );
    }

    // More fail cases to add.
    function testSetMarkets() public {
        IMarketConfiguration.MarketConfiguration memory config = manager
            .getMarketConfiguration(GmxFrfStrategyMetadata.GMX_V2_ETH_USDC);

        // Verify order pricing parameters.
        IMarketConfiguration.OrderPricingParameters
            memory expectedPricingParams = _defaultPricingParams();
        assertEq(
            config.orderPricingParameters.minOrderSizeUsd,
            expectedPricingParams.minOrderSizeUsd,
            "Min order size USD does not match"
        );
        assertEq(
            config.orderPricingParameters.maxOrderSizeUsd,
            expectedPricingParams.maxOrderSizeUsd,
            "Max order size USD does not match"
        );
        assertEq(
            config.orderPricingParameters.maxPositionSlippagePercent,
            expectedPricingParams.maxPositionSlippagePercent,
            "Max slippage percentage does not match"
        );
        assertEq(
            config.orderPricingParameters.increaseEnabled,
            expectedPricingParams.increaseEnabled,
            "Increase enabled does not match"
        );

        // Verify position parameters.
        IMarketConfiguration.PositionParameters
            memory expectedPositionParams = _defaultPositionParameters();
        assertEq(
            config.positionParameters.minPositionSizeUsd,
            expectedPositionParams.minPositionSizeUsd,
            "Min position size USD does not match"
        );
        assertEq(
            config.positionParameters.maxPositionSizeUsd,
            expectedPositionParams.maxPositionSizeUsd,
            "Max position size USD does not match"
        );
    }

    // ==================== Execute Create Increase Order Tests ====================

    function testExecuteCreateIncreaseOrderMarketDoesNotExist() public {
        _expectRevert(
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
        etched.executeCreateIncreaseOrder{ value: 1 ether }(
            address(1),
            1e10,
            1 ether
        );
    }

    function testExecuteIncreaseOrderNoLoan() public {
        IGmxFrfStrategyAccount acct = IGmxFrfStrategyAccount(
            bank.executeOpenAccount(address(this))
        );
        _expectRevert("Account has no loan.");
        acct.executeCreateIncreaseOrder{ value: 1 ether }(
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            1e10,
            1 ether
        );
    }

    function testExecuteCreateIncreaseOrderPositionSizeToSmall() public {
        GmxFrfStrategyMetadata.USDC.transfer(address(account), 1e6);
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_VALIDATION_ORDER_SIZE_IS_TOO_SMALL
        );
        account.executeCreateIncreaseOrder{ value: 1 ether }(
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            1e6,
            1 ether
        );
    }

    function testExecuteCreateIncreaseOrderOrderSizeTooLarge() public {
        GmxFrfStrategyMetadata.USDC.transfer(address(account), 1e12);
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_VALIDATION_ORDER_SIZE_IS_TOO_LARGE
        );
        account.executeCreateIncreaseOrder{ value: 1 ether }(
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            1e12,
            1 ether
        );
    }

    function testExecuteCreateIncreaseOrderPositionDoesNotYetExist() public {
        GmxFrfStrategyMetadata.USDC.transfer(address(account), 1e10);

        positionNow = PositionStoreUtils.getPositionKey(
            address(account),
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            address(GmxFrfStrategyMetadata.WETH),
            false
        );

        (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        ) = account.executeCreateIncreaseOrder{ value: 1 ether }(
                GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
                1e9,
                1 ether
            );

        _logCreateOrder(order);

        _simulateOrderExecution(
            orderKey,
            address(GmxFrfStrategyMetadata.USDC),
            address(GmxFrfStrategyMetadata.WETH)
        );
    }

    function testExecuteCreateIncreaseOrderPositionAlreadyExists() public {
        positionNow = PositionStoreUtils.getPositionKey(
            address(etched),
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            address(GmxFrfStrategyMetadata.WETH),
            false
        );

        GmxFrfStrategyMetadata.USDC.transfer(address(etched), 1e10);

        (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        ) = etched.executeCreateIncreaseOrder{ value: 1 ether }(
                GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
                1e9,
                1 ether
            );

        _logCreateOrder(order);
        _logAccountBalances(msg.sender);

        _simulateOrderExecution(
            orderKey,
            address(GmxFrfStrategyMetadata.USDC),
            address(GmxFrfStrategyMetadata.WETH)
        );
    }

    // ==================== Execute Create Decrease Order Tests ====================

    function testExecuteCreateDecreaseOrderInvalidMarket() public {
        _expectRevert(
            GmxFrfStrategyErrors.GMX_FRF_STRATEGY_MARKET_DOES_NOT_EXIST
        );
        etched.executeCreateDecreaseOrder{ value: 1 ether }(
            address(1),
            1e10,
            1 ether
        );
    }

    function testExecuteCreateDecreaseOrderNoPosition() public {
        _expectRevert(
            GmxFrfStrategyErrors.ORDER_VALIDATION_POSITION_DOES_NOT_EXIST
        );
        account.executeCreateDecreaseOrder{ value: 1 ether }(
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            1e33,
            1 ether
        );
    }

    function testExecuteCreateDecreaseOrderBasic() public {
        positionNow = PositionStoreUtils.getPositionKey(
            address(etched),
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            address(GmxFrfStrategyMetadata.WETH),
            false
        );

        (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        ) = etched.executeCreateDecreaseOrder{ value: 1 ether }(
                GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
                2e31,
                1 ether
            );

        _logCreateOrder(order);

        _simulateOrderExecution(
            orderKey,
            address(GmxFrfStrategyMetadata.USDC),
            address(GmxFrfStrategyMetadata.WETH)
        );
    }

    // ==================== Execute Swap Rebalance Tests ====================

    function testExecuteSwapRebalanceNotEnoughReturned() public {
        IGmxFrfStrategyAccount.CallbackConfig
            memory callbackConfig = IGmxFrfStrategyAccount.CallbackConfig(
                address(this),
                address(this),
                type(uint256).max
            );

        liquidatedAssetsOffset = -1;

        vm.expectRevert();
        etched.executeSwapRebalance(
            GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
            callbackConfig
        );
    }

    function testExecuteSwapRebalanceDeltaIsNegative() public {
        IGmxFrfStrategyAccount.CallbackConfig
            memory callbackConfig = IGmxFrfStrategyAccount.CallbackConfig(
                address(this),
                address(this),
                type(uint256).max
            );

        vm.expectRevert();
        etched.executeSwapRebalance(
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            callbackConfig
        );
    }

    function testExecuteSwapRebalanceDeltaProportionIsNotSufficient() public {
        IGmxFrfStrategyAccount.CallbackConfig
            memory callbackConfig = IGmxFrfStrategyAccount.CallbackConfig(
                address(this),
                address(this),
                type(uint256).max
            );

        vm.expectRevert();
        etched.executeSwapRebalance(
            GmxFrfStrategyMetadata.GMX_V2_WBTC_USDC_MARKET,
            callbackConfig
        );
    }

    function testExecuteSwapRebalanceHasActiveOrders() public {
        GmxFrfStrategyMetadata.USDC.transfer(address(etched), 1e8);

        IGmxFrfStrategyAccount.CallbackConfig
            memory callbackConfig = IGmxFrfStrategyAccount.CallbackConfig(
                address(this),
                address(this),
                type(uint256).max
            );

        etched.executeCreateIncreaseOrder{ value: 1 ether }(
            GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
            1e8,
            1 ether
        );

        vm.expectRevert();
        etched.executeSwapRebalance(
            GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
            callbackConfig
        );
    }

    function testExecuteSwapRebalance() public {
        IGmxFrfStrategyAccount.CallbackConfig
            memory callbackConfig = IGmxFrfStrategyAccount.CallbackConfig(
                address(this),
                address(this),
                type(uint256).max
            );

        etched.executeSwapRebalance(
            GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
            callbackConfig
        );
    }

    // ==================== Execute Rebalance Position Tests ====================

    function testExecuteRebalancePositionDeltaIsShort() public {
        (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        ) = etched.executeRebalancePosition{ value: 1 ether }(
                GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
                1 ether
            );

        positionNow = PositionStoreUtils.getPositionKey(
            address(etched),
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            address(GmxFrfStrategyMetadata.WETH),
            false
        );
        _logCreateOrder(order);

        _simulateOrderExecution(
            orderKey,
            address(GmxFrfStrategyMetadata.USDC),
            address(GmxFrfStrategyMetadata.WETH)
        );
    }

    function testExecuteRebalancePositionDeltaIsLongInCollateral() public {
        (
            IGmxV2OrderTypes.CreateOrderParams memory order,
            bytes32 orderKey
        ) = etched.executeRebalancePosition{ value: 1 ether }(
                GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
                1 ether
            );

        positionNow = PositionStoreUtils.getPositionKey(
            address(etched),
            GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
            address(GmxFrfStrategyMetadata.ARB),
            false
        );

        _logCreateOrder(order);

        _simulateOrderExecution(
            orderKey,
            address(GmxFrfStrategyMetadata.USDC),
            address(GmxFrfStrategyMetadata.ARB)
        );
    }

    // ==================== Releverage Position Tests ====================

    function testGetLeverage() public {
        // uint256 leverage =
        //     DeltaConvergenceMath.getPositionLeverage(manager, GmxFrfStrategyMetadata.GMX_V2_ETH_USDC, address(etched));
        // console.log(leverage);
    }

    // ==================== Helper Functions ====================

    function _simulateOrderExecution(
        bytes32 orderKey,
        address shortToken,
        address longToken
    ) private {
        IGmxV2ExchangeRouter.SimulatePricesParams
            memory simulatedOracleParams = IGmxV2ExchangeRouter
                .SimulatePricesParams(
                    new address[](2),
                    new IGmxV2PriceTypes.Props[](2)
                );

        uint256 shortTokenPrice = Pricing.getUnitTokenPriceUSD(
            manager,
            address(shortToken)
        );
        uint256 longTokenPrice = Pricing.getUnitTokenPriceUSD(
            manager,
            address(longToken)
        );

        simulatedOracleParams.primaryTokens[0] = shortToken;
        simulatedOracleParams.primaryTokens[1] = longToken;

        simulatedOracleParams.primaryPrices[0] = IGmxV2PriceTypes.Props(
            shortTokenPrice,
            shortTokenPrice
        );

        simulatedOracleParams.primaryPrices[1] = IGmxV2PriceTypes.Props(
            longTokenPrice,
            longTokenPrice
        );
        try
            manager.gmxV2ExchangeRouter().simulateExecuteOrder(
                orderKey,
                simulatedOracleParams
            )
        {} catch Error(string memory reason) {
            console.log(reason);
        }
    }

    function _getMarketPrices(
        address market
    ) private view returns (IGmxV2MarketTypes.MarketPrices memory prices) {
        uint256 shortTokenPrice = Pricing.getUnitTokenPriceUSD(
            manager,
            GmxMarketGetters.getShortToken(manager.gmxV2DataStore(), market)
        );
        uint256 longTokenPrice = Pricing.getUnitTokenPriceUSD(
            manager,
            GmxMarketGetters.getLongToken(manager.gmxV2DataStore(), market)
        );
        return
            IGmxV2MarketTypes.MarketPrices(
                IGmxV2PriceTypes.Props(longTokenPrice, longTokenPrice),
                IGmxV2PriceTypes.Props(longTokenPrice, longTokenPrice),
                IGmxV2PriceTypes.Props(shortTokenPrice, shortTokenPrice)
            );
    }

    function _etchToPositionHolder(
        address positionHolder
    ) private returns (IGmxFrfStrategyAccount etchedAccount) {
        // Transfer out holder's assets for clean environment.

        uint256 usdcBalance = GmxFrfStrategyMetadata.USDC.balanceOf(
            positionHolder
        );

        vm.prank(positionHolder);

        GmxFrfStrategyMetadata.USDC.transfer(address(1), usdcBalance);

        uint256 wethBalance = GmxFrfStrategyMetadata.WETH.balanceOf(
            positionHolder
        );
        vm.prank(positionHolder);
        GmxFrfStrategyMetadata.WETH.transfer(address(1), wethBalance);

        uint256 arbBalance = GmxFrfStrategyMetadata.ARB.balanceOf(
            positionHolder
        );
        vm.prank(positionHolder);
        GmxFrfStrategyMetadata.ARB.transfer(address(1), arbBalance);

        uint256 wbtcBalance = GmxFrfStrategyMetadata.WBTC.balanceOf(
            positionHolder
        );

        vm.prank(positionHolder);
        GmxFrfStrategyMetadata.WBTC.transfer(address(1), wbtcBalance);

        vm.prank(positionHolder);

        payable(address(12031230)).transfer(positionHolder.balance);

        vm.etch(positionHolder, address(account).code);

        return IGmxFrfStrategyAccount(positionHolder);
    }

    function _logCreateOrder(
        IGmxV2OrderTypes.CreateOrderParams memory order
    ) private view {
        console.log(
            "======================= Create Order ======================="
        );
        console.log("SizeDeltaUsd:", order.numbers.sizeDeltaUsd);
        console.log(
            "InitialCollateralDeltaAmount:",
            order.numbers.initialCollateralDeltaAmount
        );
        console.log("TriggerPrice:", order.numbers.triggerPrice);
        console.log("AcceptablePrice:", order.numbers.acceptablePrice);
        console.log("ExecutionFee:", order.numbers.executionFee);
        console.log("CallbackGasLimit:", order.numbers.callbackGasLimit);
        console.log("MinOutputAmount:", order.numbers.minOutputAmount);

        console.log("Receiver", order.addresses.receiver);
        console.log("CallbackContract", order.addresses.callbackContract);
        console.log("UiFeeReceiver", order.addresses.uiFeeReceiver);
        console.log("Market", order.addresses.market);
        console.log(
            "InitialCollateralToken",
            order.addresses.initialCollateralToken
        );

        for (uint256 i = 0; i < order.addresses.swapPath.length; i++) {
            console.log("SwapPath ", i, order.addresses.swapPath[i]);
        }

        console.log("OrderType:", uint256(order.orderType));
        console.log("IsLong:", order.isLong);
        console.log("ShouldUnwrapNativeToken", order.shouldUnwrapNativeToken);
        // console.log(order.referralCode);
    }

    function _logOrderProps(IGmxV2OrderTypes.Props memory order) private view {
        console.log("======================= Order =======================");
        console.log("SizeDeltaUsd:", order.numbers.sizeDeltaUsd);
        console.log(
            "InitialCollateralDeltaAmount:",
            order.numbers.initialCollateralDeltaAmount
        );
        console.log("TriggerPrice:", order.numbers.triggerPrice);
        console.log("AcceptablePrice:", order.numbers.acceptablePrice);
        console.log("ExecutionFee:", order.numbers.executionFee);
        console.log("CallbackGasLimit:", order.numbers.callbackGasLimit);
        console.log("MinOutputAmount:", order.numbers.minOutputAmount);

        console.log("Receiver", order.addresses.receiver);
        console.log("CallbackContract", order.addresses.callbackContract);
        console.log("UiFeeReceiver", order.addresses.uiFeeReceiver);
        console.log("Market", order.addresses.market);
        console.log(
            "InitialCollateralToken",
            order.addresses.initialCollateralToken
        );

        for (uint256 i = 0; i < order.addresses.swapPath.length; i++) {
            console.log("SwapPath ", i, order.addresses.swapPath[i]);
        }

        // console.log(order.referralCode);
    }

    function _logPositionInfo(
        IGmxV2PositionTypes.PositionInfo memory info
    ) private view {
        _logPosition(info.position);
        console.log(
            "======================= Position fees ======================="
        );

        console.log("Funding Fee Amount:", info.fees.funding.fundingFeeAmount);
        console.log(
            "Claimable Long Token Amount:",
            info.fees.funding.claimableLongTokenAmount
        );

        console.log(
            "Claimable Short Token Amount:",
            info.fees.funding.claimableShortTokenAmount
        );

        console.log(
            "Latest Funding Fee Amount Per Size:",
            info.fees.funding.latestFundingFeeAmountPerSize
        );

        console.log(
            "Latest Long Token Claimable Funding Amount Per Size:",
            info.fees.funding.latestLongTokenClaimableFundingAmountPerSize
        );

        console.log(
            "Latest Short Token Claimable Funding Amount Per Size:",
            info.fees.funding.latestShortTokenClaimableFundingAmountPerSize
        );
        console.log("Borrow fee USD", info.fees.borrowing.borrowingFeeUsd);
        console.log(
            "Borrowing Fee Amount:",
            info.fees.borrowing.borrowingFeeAmount
        );
        console.log(
            "Borrowing Fee Receiever Factor:",
            info.fees.borrowing.borrowingFeeReceiverFactor
        );
        console.log(
            "Borrowing Fee Amount For Fee Receiver:",
            info.fees.borrowing.borrowingFeeAmountForFeeReceiver
        );

        console.log(
            "Total Cost Amount Excluding Funding:",
            info.fees.totalCostAmountExcludingFunding
        );

        _logInt256(
            "Price Impact USD:",
            info.executionPriceResult.priceImpactUsd
        );

        console.log(
            "Price Impact Diff USD:",
            info.executionPriceResult.priceImpactDiffUsd
        );
        console.log(
            "Execution Price:",
            info.executionPriceResult.executionPrice
        );

        _logInt256("Base Pnl USD:", info.basePnlUsd);
        _logInt256("Uncapped Base Pnl USD:", info.uncappedBasePnlUsd);
        _logInt256("Pnl After Price Impact USD:", info.pnlAfterPriceImpactUsd);
    }

    function _logInt256(string memory label, int256 value) private view {
        if (value >= 0) {
            console.log(label, uint256(value));
        } else {
            console.log(label, " -", uint256(-value));
        }
    }

    function _logPosition(
        IGmxV2PositionTypes.Props memory position
    ) private view {
        console.log("======================= Position =======================");
        console.log("Market:", position.addresses.market);
        console.log("CollateralToken:", position.addresses.collateralToken);
        console.log("Size in USD", position.numbers.sizeInUsd);
        console.log("Size in tokens", position.numbers.sizeInTokens);
        console.log("Collateral amount", position.numbers.collateralAmount);
        console.log("Borrowing factor", position.numbers.borrowingFactor);
        console.log(
            "Funding fee amount per size",
            position.numbers.fundingFeeAmountPerSize
        );
        console.log(
            "Long token claimable funding amount per size",
            position.numbers.longTokenClaimableFundingAmountPerSize
        );
        console.log(
            "Short token claimable funding amount per size",
            position.numbers.shortTokenClaimableFundingAmountPerSize
        );
        console.log("Increased at block", position.numbers.increasedAtBlock);
        console.log("Decreased at block", position.numbers.decreasedAtBlock);
        console.log("Is Long:", position.flags.isLong);
    }

    function _defaultPricingParams()
        internal
        pure
        returns (IMarketConfiguration.OrderPricingParameters memory)
    {
        return
            IMarketConfiguration.OrderPricingParameters(
                0.1e18, // 3%
                0.1e18, // 3%
                1e31, // $10
                1e35, // $100k
                true
            );
    }

    function _defaultUnwindParameters()
        internal
        pure
        returns (IMarketConfiguration.UnwindParameters memory)
    {
        return
            IMarketConfiguration.UnwindParameters(
                1.05e18, // 1.05 delta ratio (i.e. min(short, long) / max(short, long) < 1.05)
                5e30, // $10
                1.3e18, // 1.3x leverage.
                0.03e18
            );
    }

    function _defaultPositionParameters()
        internal
        pure
        returns (IMarketConfiguration.PositionParameters memory)
    {
        return
            IMarketConfiguration.PositionParameters(
                1e31, // $10
                1e36 // $1m
            );
    }

    function _logAccountBalances(address acc) private view {
        console.log("================== Account Balances ==================");
        console.log(
            "USDC balance:",
            GmxFrfStrategyMetadata.USDC.balanceOf(acc)
        );
        console.log(
            "WETH balance:",
            GmxFrfStrategyMetadata.WETH.balanceOf(acc)
        );
        console.log("ARB balance:", GmxFrfStrategyMetadata.ARB.balanceOf(acc));
        console.log(
            "WBTC balance:",
            GmxFrfStrategyMetadata.WBTC.balanceOf(acc)
        );
        console.log("ETH balance:", acc.balance);
    }

    function _logClaimableFundingFees(address acc) private view {
        IGmxV2DataStore dataStore = manager.gmxV2DataStore();

        uint256 usdc1 = GmxStorageGetters.getClaimableFundingFees(
            dataStore,
            GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
            address(GmxFrfStrategyMetadata.USDC),
            acc
        );

        uint256 arb1 = GmxStorageGetters.getClaimableFundingFees(
            dataStore,
            GmxFrfStrategyMetadata.GMX_V2_ARB_USDC_MARKET,
            address(GmxFrfStrategyMetadata.ARB),
            acc
        );

        console.log("================== ARB/USDC ==================");
        console.log("Claimable USDC:", usdc1);
        console.log("Claimable ARB:", arb1);

        uint256 usdc2 = GmxStorageGetters.getClaimableFundingFees(
            dataStore,
            GmxFrfStrategyMetadata.GMX_V2_WBTC_USDC_MARKET,
            address(GmxFrfStrategyMetadata.USDC),
            acc
        );

        uint256 wbtc2 = GmxStorageGetters.getClaimableFundingFees(
            dataStore,
            GmxFrfStrategyMetadata.GMX_V2_WBTC_USDC_MARKET,
            address(GmxFrfStrategyMetadata.WBTC),
            acc
        );

        console.log("================== WBTC/USDC ==================");
        console.log("Claimable USDC:", usdc2);
        console.log("Claimable WBTC:", wbtc2);

        uint256 usdc3 = GmxStorageGetters.getClaimableFundingFees(
            dataStore,
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            address(GmxFrfStrategyMetadata.USDC),
            acc
        );

        uint256 weth3 = GmxStorageGetters.getClaimableFundingFees(
            dataStore,
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC,
            address(GmxFrfStrategyMetadata.WETH),
            acc
        );

        console.log("================== WETH/USDC ==================");
        console.log("Claimable USDC:", usdc3);
        console.log("Claimable WETH:", weth3);
    }

    receive() external payable {
        vm.pauseGasMetering();

        IGmxV2MarketTypes.MarketPrices memory marketPrices = _getMarketPrices(
            GmxFrfStrategyMetadata.GMX_V2_ETH_USDC
        );

        console.log(
            marketPrices.longTokenPrice.min,
            marketPrices.shortTokenPrice.min
        );

        IGmxV2PositionTypes.PositionInfo memory info = manager
            .gmxV2Reader()
            .getPositionInfo(
                manager.gmxV2DataStore(),
                GmxFrfStrategyMetadata.GMX_V2_REFERRAL_STORAGE,
                positionNow,
                marketPrices,
                0,
                address(0),
                true
            );

        _logPositionInfo(info);

        _logAccountBalances(msg.sender);

        vm.resumeGasMetering();
    }

    function _expectRevert(string memory revertMsg) internal {
        vm.expectRevert(bytes(revertMsg));
    }
}

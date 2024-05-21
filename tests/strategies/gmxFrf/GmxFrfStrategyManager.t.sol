// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    Initializable
} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    GmxFrfStrategyManager
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyManager.sol";
import {
    IGmxFrfStrategyManager
} from "../../../contracts/strategies/gmxFrf/interfaces/IGmxFrfStrategyManager.sol";
import {
    IDeploymentConfiguration
} from "../../../contracts/strategies/gmxFrf/interfaces/IDeploymentConfiguration.sol";
import {
    IMarketConfiguration
} from "../../../contracts/strategies/gmxFrf/interfaces/IMarketConfiguration.sol";
import { GmxFrfStrategyMetadata } from "./GmxFrfStrategyMetadata.sol";
import {
    IMarketConfiguration
} from "../../../contracts/strategies/gmxFrf/interfaces/IMarketConfiguration.sol";
import {
    IChainlinkAdapter
} from "../../../contracts/adapters/chainlink/interfaces/IChainlinkAdapter.sol";
import {
    IChainlinkAggregatorV3
} from "../../../contracts/adapters/chainlink/interfaces/external/IChainlinkAggregatorV3.sol";
import { IStrategyBank } from "../../../contracts/interfaces/IStrategyBank.sol";
import {
    IStrategyController
} from "../../../contracts/interfaces/IStrategyController.sol";
import { StateManager } from "../../StateManager.sol";
import {
    GmxFrfStrategyErrors
} from "../../../contracts/strategies/gmxFrf/GmxFrfStrategyErrors.sol";
import { Errors } from "../../../contracts/libraries/Errors.sol";
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
    IGmxV2ReferralStorage
} from "../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2ReferralStorage.sol";
import { StrategyDeployerHelper } from "./StrategyDeployerHelper.sol";
import { GmxV2ReaderMock } from "../../mocks/GmxV2ReaderMock.sol";

contract GmxFrfStrategyManagerTest is StrategyDeployerHelper, StateManager {
    IGmxFrfStrategyManager manager;
    ProxyAdmin managerProxyAdmin;

    function setUp() public {
        // ==================== Setup ====================

        IChainlinkAdapter.OracleConfiguration memory oc = IChainlinkAdapter
            .OracleConfiguration(1e6, GmxFrfStrategyMetadata.USDC_USD_ORACLE);
        (manager, managerProxyAdmin) = deployManager(oc);
    }

    // ==================== Constructor ====================

    constructor() StateManager(false) {}

    // ==================== Upgradeability Tests ====================

    function testInitialization() public {
        // Check immutables.
        assertEq(address(manager.USDC()), address(GmxFrfStrategyMetadata.USDC));
        assertEq(
            address(manager.WRAPPED_NATIVE_TOKEN()),
            address(GmxFrfStrategyMetadata.WETH)
        );

        // Check initial storage (deployment config manager).
        assertEq(
            address(manager.gmxV2ExchangeRouter()),
            address(GmxFrfStrategyMetadata.GMX_V2_EXCHANGE_ROUTER)
        );
        assertEq(
            address(manager.gmxV2OrderVault()),
            address(GmxFrfStrategyMetadata.GMX_V2_ORDER_VAULT)
        );
        assertEq(
            address(manager.gmxV2Reader()),
            address(GmxFrfStrategyMetadata.GMX_V2_READER)
        );
        assertEq(
            address(manager.gmxV2DataStore()),
            address(GmxFrfStrategyMetadata.GMX_V2_DATASTORE)
        );
        assertEq(
            address(manager.gmxV2RoleStore()),
            address(GmxFrfStrategyMetadata.GMX_V2_ROLESTORE)
        );
        assertEq(
            address(manager.gmxV2ReferralStorage()),
            address(GmxFrfStrategyMetadata.GMX_V2_REFERRAL_STORAGE)
        );
        assertEq(manager.getProfitWithdrawalBufferPercent(), 1.1e18);
    }

    function testLogicInitializerCannotBeCalled() public {
        bytes32 logicSlot = vm.load(
            address(manager),
            ERC1967Utils.IMPLEMENTATION_SLOT
        );
        address logic = address(uint160(uint256(logicSlot)));

        IDeploymentConfiguration.Deployments memory deployments;
        IMarketConfiguration.SharedOrderParameters memory orderParams;
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        GmxFrfStrategyManager(logic).initialize(
            deployments,
            orderParams,
            IChainlinkAdapter.OracleConfiguration(
                1e6,
                IChainlinkAggregatorV3(address(1))
            ),
            0
        );
    }

    function testInitializerCannotBeCalledAgain() public {
        IDeploymentConfiguration.Deployments memory deployments;
        IMarketConfiguration.SharedOrderParameters memory orderParams;
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        GmxFrfStrategyManager(address(manager)).initialize(
            deployments,
            orderParams,
            IChainlinkAdapter.OracleConfiguration(
                1e6,
                IChainlinkAggregatorV3(address(1))
            ),
            0
        );
    }

    function testUpgrade() public {
        // Deploy new logic contract (no actual changes to logic).
        address newLogic = address(
            new GmxFrfStrategyManager(
                GmxFrfStrategyMetadata.USDC,
                GmxFrfStrategyMetadata.WETH,
                address(this)
            )
        );

        // Perform upgrade to the new logic contract (initializer is not called again).
        managerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(manager)),
            newLogic,
            bytes("") // no initialization
        );

        // Sanity check that the logic address was updated.
        bytes32 logicSlot = vm.load(
            address(manager),
            ERC1967Utils.IMPLEMENTATION_SLOT
        );
        assertEq(newLogic, address(uint160(uint256(logicSlot))));

        // Sanity check that initializer cannot be called.
        IDeploymentConfiguration.Deployments memory deployments;
        IMarketConfiguration.SharedOrderParameters memory orderParams;
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        GmxFrfStrategyManager(address(manager)).initialize(
            deployments,
            orderParams,
            IChainlinkAdapter.OracleConfiguration(
                1e6,
                IChainlinkAggregatorV3(address(1))
            ),
            0
        );

        // Sanity check that state is still as expected.
        assertEq(
            address(manager.gmxV2ExchangeRouter()),
            address(GmxFrfStrategyMetadata.GMX_V2_EXCHANGE_ROUTER)
        );
    }

    function testCannotRenounceOwnership() public {
        _expectRevert(Errors.CANNOT_RENOUNCE_OWNERSHIP);
        GmxFrfStrategyManager(address(manager)).renounceOwnership();
    }

    // ==================== Set Exchange Router Tests ====================

    function testSetExchangeRouterZeroRouter() public {
        _expectRevert(GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        manager.setExchangeRouter(IGmxV2ExchangeRouter(address(0)));
    }

    // ==================== Set Order Vault Tests ====================

    function testSetOrderVaultZeroVault() public {
        _expectRevert(GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        manager.setOrderVault(address(0));
    }

    // ==================== Set Reader Tests ====================

    function testSetReaderZeroReader() public {
        _expectRevert(GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        manager.setReader(IGmxV2Reader(address(0)));
    }

    // ==================== Set Data Store Tests ====================

    function testSetDataStoreZeroStore() public {
        _expectRevert(GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        manager.setDataStore(IGmxV2DataStore(address(0)));
    }

    // ==================== Set Role Store Tests ====================

    function testSetRoleStoreZeroStore() public {
        _expectRevert(GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        manager.setRoleStore(IGmxV2RoleStore(address(0)));
    }

    // ==================== Set Referral Storage Tests ====================

    function testSetReferralStorageZeroStorage() public {
        _expectRevert(GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        manager.setReferralStorage(IGmxV2ReferralStorage(address(0)));
    }

    // ==================== Set Market Tests ====================

    function testSetMarketAndUpdate() public {
        GmxV2ReaderMock reader = new GmxV2ReaderMock();
        manager.setReader(IGmxV2Reader(address(reader)));

        IChainlinkAdapter.OracleConfiguration
            memory oracleConfig = IChainlinkAdapter.OracleConfiguration(
                100,
                GmxFrfStrategyMetadata.USDC_USD_ORACLE
            );

        manager.setMarket(
            address(1),
            oracleConfig,
            _defaultPricingParams(),
            _defaultPositionParameters(),
            _defaultUnwindParameters(),
            2e16
        );

        manager.setMarket(
            address(1),
            oracleConfig,
            _defaultPricingParams(),
            _defaultPositionParameters(),
            _defaultUnwindParameters(),
            2e16
        );
    }

    function testSetMarketTwoMarketsWithTheSameLongToken() public {
        GmxV2ReaderMock reader = new GmxV2ReaderMock();
        manager.setReader(IGmxV2Reader(address(reader)));

        IChainlinkAdapter.OracleConfiguration
            memory oracleConfig = IChainlinkAdapter.OracleConfiguration(
                100,
                GmxFrfStrategyMetadata.USDC_USD_ORACLE
            );

        manager.setMarket(
            reader.collision(),
            oracleConfig,
            _defaultPricingParams(),
            _defaultPositionParameters(),
            _defaultUnwindParameters(),
            2e16
        );

        // Cannot call functions inside of `setMarket` given the expect revert.
        address market = reader.collision2();
        IMarketConfiguration.OrderPricingParameters
            memory marketParameters = _defaultPricingParams();
        IMarketConfiguration.PositionParameters
            memory positionParameters = _defaultPositionParameters();
        IMarketConfiguration.UnwindParameters
            memory unwindParameters = _defaultUnwindParameters();

        _expectRevert(
            GmxFrfStrategyErrors.CANNOT_ADD_SEPERATE_MARKET_WITH_SAME_LONG_TOKEN
        );
        manager.setMarket(
            market,
            oracleConfig,
            marketParameters,
            positionParameters,
            unwindParameters,
            2e16
        );
    }

    function testSetMarketTwoMarketsWithTheDifferentLongToken() public {
        GmxV2ReaderMock reader = new GmxV2ReaderMock();
        manager.setReader(IGmxV2Reader(address(reader)));

        IChainlinkAdapter.OracleConfiguration
            memory oracleConfig = IChainlinkAdapter.OracleConfiguration(
                100,
                GmxFrfStrategyMetadata.USDC_USD_ORACLE
            );

        manager.setMarket(
            msg.sender,
            oracleConfig,
            _defaultPricingParams(),
            _defaultPositionParameters(),
            _defaultUnwindParameters(),
            2e16
        );

        manager.setMarket(
            address(this),
            oracleConfig,
            _defaultPricingParams(),
            _defaultPositionParameters(),
            _defaultUnwindParameters(),
            2e16
        );
    }

    // ==================== Utilities ====================

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
}

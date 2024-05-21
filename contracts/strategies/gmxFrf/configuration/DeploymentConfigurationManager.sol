// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IWrappedNativeToken
} from "../../../adapters/shared/interfaces/IWrappedNativeToken.sol";
import {
    IGmxV2PositionTypes
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";
import {
    IGmxV2Reader
} from "../../../lib/gmx/interfaces/external/IGmxV2Reader.sol";
import {
    IGmxV2DataStore
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2DataStore.sol";
import {
    IGmxV2RoleStore
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2RoleStore.sol";
import {
    IGmxV2ReferralStorage
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2ReferralStorage.sol";
import {
    IWrappedNativeToken
} from "../../../adapters/shared/interfaces/IWrappedNativeToken.sol";
import {
    IDeploymentConfiguration
} from "../interfaces/IDeploymentConfiguration.sol";
import { GmxFrfStrategyErrors } from "../GmxFrfStrategyErrors.sol";
import {
    IGmxV2ExchangeRouter
} from "../../../strategies/gmxFrf/interfaces/gmx/IGmxV2ExchangeRouter.sol";
import { ISwapCallbackRelayer } from "../interfaces/ISwapCallbackRelayer.sol";
import { SwapCallbackRelayer } from "../SwapCallbackRelayer.sol";

/**
 * @title DeploymentConfigurationManager
 * @author GoldLink
 *
 * @dev Manages the deployment configuration for the GMX V2.
 */
abstract contract DeploymentConfigurationManager is
    IDeploymentConfiguration,
    Initializable
{
    // ============ Constants ============

    /// @notice Usdc token address.
    IERC20 public immutable USDC;

    /// @notice Wrapped native ERC20 token address.
    IWrappedNativeToken public immutable WRAPPED_NATIVE_TOKEN;

    /// @notice Callback Relayer address for swap callback security.
    ISwapCallbackRelayer public immutable SWAP_CALLBACK_RELAYER;

    /// @notice The collateral claim distributor address. In the event that the GMX team
    /// issues a collateral stipend and the account was liquidated after, this address will
    /// receive it and subsequently be responsible for distributing it.
    address public immutable COLLATERAL_CLAIM_DISTRIBUTOR;

    // ============ Storage Variables ============

    /// @dev GMX V2 ExchangeRouter.
    IGmxV2ExchangeRouter private gmxV2ExchangeRouter_;

    /// @dev GMX V2 order vault address.
    address private gmxV2OrderVault_;

    /// @dev GMX V2 `Reader` deployment address.
    IGmxV2Reader private gmxV2Reader_;

    /// @dev GMX V2 `DataStore` deployment address.
    IGmxV2DataStore private gmxV2DataStore_;

    /// @dev GMX V2 `RoleStore` deployment address.
    IGmxV2RoleStore private gmxV2RoleStore_;

    /// @dev Gmx V2 `ReferralStorage` deployment address.
    IGmxV2ReferralStorage private gmxV2ReferralStorage_;

    /**
     * @dev This is empty reserved space intended to allow future versions of this upgradeable
     *  contract to define new variables without shifting down storage in the inheritance chain.
     *  See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[44] private __gap;

    // ============ Modifiers ============

    /// @dev Verify the address is not the zero address.
    modifier onlyNonZeroAddress(address addressToCheck) {
        require(
            addressToCheck != address(0),
            GmxFrfStrategyErrors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Constructor for upgradeable contract, distinct from initializer.
     *
     *  The constructor is used to set immutable variables, and for top-level upgradeable
     *  contracts, it is also used to disable the initializer of the logic contract.
     */
    constructor(
        IERC20 _usdc,
        IWrappedNativeToken _wrappedNativeToken,
        address _collateralClaimDistributor
    )
        onlyNonZeroAddress(address(_usdc))
        onlyNonZeroAddress(address(_wrappedNativeToken))
        onlyNonZeroAddress(_collateralClaimDistributor)
    {
        USDC = _usdc;
        WRAPPED_NATIVE_TOKEN = _wrappedNativeToken;
        COLLATERAL_CLAIM_DISTRIBUTOR = _collateralClaimDistributor;
        SWAP_CALLBACK_RELAYER = ISwapCallbackRelayer(new SwapCallbackRelayer());
    }

    // ============ Initializer ============

    function __DeploymentConfigurationManager_init(
        Deployments calldata deployments
    ) internal onlyInitializing {
        __DeploymentConfigurationManager_init_unchained(deployments);
    }

    function __DeploymentConfigurationManager_init_unchained(
        Deployments calldata deployments
    ) internal onlyInitializing {
        _setExchangeRouter(deployments.exchangeRouter);
        _setOrderVault(deployments.orderVault);
        _setReader(deployments.reader);
        _setDataStore(deployments.dataStore);
        _setRoleStore(deployments.roleStore);
        _setReferralStorage(deployments.referralStorage);
    }

    // ============ Public Functions ============

    /**
     * @notice Get the cached deployment address for the GMX V2 ExchangeRouter.
     * @return gmxV2ExchangeRouter The deployment address for the GMX V2 ExchangeRouter.
     */
    function gmxV2ExchangeRouter()
        public
        view
        override
        returns (IGmxV2ExchangeRouter)
    {
        return gmxV2ExchangeRouter_;
    }

    /**
     * @notice Get the cached deployment address for the GMX V2 OrderVault.
     * @return gmxV2OrderVault The deployment address for the GMX V2 OrderVault.
     */
    function gmxV2OrderVault() public view override returns (address) {
        return gmxV2OrderVault_;
    }

    /**
     * @notice Get the cached deployment address for the GMX V2 Reader.
     * @return gmxV2Reader The deployment address for the GMX V2 Reader.
     */
    function gmxV2Reader() public view override returns (IGmxV2Reader) {
        return gmxV2Reader_;
    }

    /**
     * @notice Get the cached deployment address for the GMX V2 DataStore.
     * @return gmxV2DataStore The deployment address for the GMX V2 DataStore.
     */
    function gmxV2DataStore() public view override returns (IGmxV2DataStore) {
        return gmxV2DataStore_;
    }

    /**
     * @notice Get the cached deployment address for the GMX V2 RoleStore.
     * @return gmxV2RoleStore The deployment address for the GMX V2 RoleStore.
     */
    function gmxV2RoleStore() public view override returns (IGmxV2RoleStore) {
        return gmxV2RoleStore_;
    }

    /**
     * @notice Get the cached deployment address for the GMX V2 ReferralStorage.
     * @return gmxV2ReferralStorage The deployment address for the GMX V2 ReferralStorage.
     */
    function gmxV2ReferralStorage()
        public
        view
        override
        returns (IGmxV2ReferralStorage)
    {
        return gmxV2ReferralStorage_;
    }

    // ============ Internal Functions ============

    /**
     * @notice Set the ExchangeRouter address for Gmx V2. Care should be taken when setting the ExchangeRouter address to ensure the strategy implementation is compatible.
     * @dev Emits the `ExchangeRouterSet()` event.
     * @param newExchangeRouter The deployment address for the GMX V2 ExchangeRouter.
     */
    function _setExchangeRouter(
        IGmxV2ExchangeRouter newExchangeRouter
    ) internal onlyNonZeroAddress(address(newExchangeRouter)) {
        gmxV2ExchangeRouter_ = newExchangeRouter;

        emit ExchangeRouterSet(address(newExchangeRouter));
    }

    /**
     * @notice Set the OrderVault address for Gmx V2. Care should be taken when setting the OrderVault address to ensure the strategy implementation is compatible.
     * @dev Emits the `OrderVaultSet()` event.
     * @param newOrderVault The deployment address for the GMX V2 OrderVault.
     */
    function _setOrderVault(
        address newOrderVault
    ) internal onlyNonZeroAddress(newOrderVault) {
        gmxV2OrderVault_ = newOrderVault;

        emit OrderVaultSet(newOrderVault);
    }

    /**
     * @notice Set the Reader address for Gmx V2. Care should be taken when setting the Reader address to ensure the strategy implementation is compatible.
     * @dev Emits the `ReaderSet()` event.
     * @param newReader The deployment address for the GMX V2 Reader.
     */
    function _setReader(
        IGmxV2Reader newReader
    ) internal onlyNonZeroAddress(address(newReader)) {
        gmxV2Reader_ = newReader;

        emit ReaderSet(address(newReader));
    }

    /**
     * @notice Set the DataStore address for Gmx V2. Care should be taken when setting the DataStore address to ensure the strategy implementation is compatible.
     * @dev Emits the `DataStoreSet()` event.
     * @param newDataStore The deployment address for the GMX V2 DataStore.
     */
    function _setDataStore(
        IGmxV2DataStore newDataStore
    ) internal onlyNonZeroAddress(address(newDataStore)) {
        gmxV2DataStore_ = newDataStore;

        emit DataStoreSet(address(newDataStore));
    }

    /**
     * @notice Set the RoleStore address for Gmx V2. Care should be taken when setting the RoleStore address to ensure the strategy implementation is compatible.
     * @dev Emits the `RoleStoreSet()` event.
     * @param newRoleStore The deployment address for the GMX V2 RoleStore.
     */
    function _setRoleStore(
        IGmxV2RoleStore newRoleStore
    ) internal onlyNonZeroAddress(address(newRoleStore)) {
        gmxV2RoleStore_ = newRoleStore;

        emit RoleStoreSet(address(newRoleStore));
    }

    /**
     * @notice Set the ReferralStorage address for Gmx V2. Care should be taken when setting the ReferralStorage address to ensure the strategy implementation is compatible.
     * @dev Emits the `ReferralStorageSet()` event.
     * @param newReferralStorage The deployment address for the GMX V2 ReferralStorage.
     */
    function _setReferralStorage(
        IGmxV2ReferralStorage newReferralStorage
    ) internal onlyNonZeroAddress(address(newReferralStorage)) {
        gmxV2ReferralStorage_ = newReferralStorage;

        emit ReferralStorageSet(address(newReferralStorage));
    }
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ChainlinkErrors } from "./ChainlinkErrors.sol";
import { IChainlinkAdapter } from "./interfaces/IChainlinkAdapter.sol";
import {
    IChainlinkAggregatorV3
} from "./interfaces/external/IChainlinkAggregatorV3.sol";
import { GoldLinkOwnable } from "../../utils/GoldLinkOwnable.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title OracleAssetRegistry
 * @author GoldLink
 *
 * @notice Handles all registered assets for a given oracle.
 *
 */
abstract contract OracleAssetRegistry is IChainlinkAdapter, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Storage Variables ============

    /// @dev Mapping of asset addresses to their corresponding oracle configurations.
    mapping(address => IChainlinkAdapter.OracleConfiguration)
        internal assetToOracle_;

    /// @dev Set containing registered assets. Used to provide a set of assets with registered oracles.
    EnumerableSet.AddressSet internal registeredAssets_;

    /**
     * @dev This is empty reserved space intended to allow future versions of this upgradeable
     *  contract to define new variables without shifting down storage in the inheritance chain.
     *  See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;

    // ============ Initializer ============

    function __OracleAssetRegistry_init(
        address strategyAsset,
        OracleConfiguration memory strategyAssetConfig
    ) internal onlyInitializing {
        __OracleAssetRegistry_init_unchained(
            strategyAsset,
            strategyAssetConfig
        );
    }

    function __OracleAssetRegistry_init_unchained(
        address strategyAsset,
        OracleConfiguration memory strategyAssetConfig
    ) internal onlyInitializing {
        _setAssetOracle(
            strategyAsset,
            strategyAssetConfig.oracle,
            strategyAssetConfig.validPriceDuration
        );
    }

    // ============ External Functions ============

    /**
     * @notice Get the price for an asset.
     * @param asset     The asset to fetch the price for. Must have a valid oracle, and the oracle's last update must be within the valid price duration.
     * @return price    The price for the asset with `decimals` amount of precision.
     * @return decimals The amount of decimals used by the oracle to represent the price of the asset / asset pair.
     */
    function getAssetPrice(
        address asset
    ) public view override returns (uint256 price, uint256 decimals) {
        return _getAssetPrice(asset);
    }

    /**
     * @notice Get the oracle address corresponding to the provided `asset`. If no oracle exists, the returned oracle address will be the zero address.
     * @param asset   The asset whose oracle is being fetched.
     * @return oracle The `IChainlinkAggregatorV3` oracle corresponding to the provided `asset`.
     */
    function getAssetOracle(
        address asset
    ) public view returns (IChainlinkAggregatorV3 oracle) {
        return assetToOracle_[asset].oracle;
    }

    /**
     * @notice Get the oracle configuration for an asset.
     * @param asset    The asset to get the oracle configuration for.
     * @return oracle  The `IChainlinkAggregatorV3` oracle corresponding to the provided `asset`.
     * @return validPriceDuration The amount of time (seconds) since the last update of the oracle that the price is still considered valid.
     */
    function getAssetOracleConfiguration(
        address asset
    )
        public
        view
        returns (IChainlinkAggregatorV3 oracle, uint256 validPriceDuration)
    {
        OracleConfiguration memory config = assetToOracle_[asset];

        return (config.oracle, config.validPriceDuration);
    }

    /**
     * @notice Get all registered assets, the assets with oracles for this contract.
     * @return assets The array of all registered assets.
     */
    function getRegisteredAssets()
        external
        view
        returns (address[] memory assets)
    {
        return registeredAssets_.values();
    }

    // ============ Internal Functions ============

    /**
     * @notice Sets the oracle configuration for the provided `asset`.
     * @dev Emits the `AssetOracleRegistered()` event.
     * @param asset  The asset that the correspond `IChainlinkAggregatorV3` provides a price feed for.
     * @param oracle The `IChainlinkAggregatorV3` that provides a price feed for the specified `asset`.
     * @param validPriceDuration The amount of time (seconds) since the last update of the oracle that the price is still considered valid.
     */
    function _setAssetOracle(
        address asset,
        IChainlinkAggregatorV3 oracle,
        uint256 validPriceDuration
    ) internal {
        require(asset != address(0), ChainlinkErrors.INVALID_ASSET_ADDRESS);

        require(
            address(oracle) != address(0),
            ChainlinkErrors.ORACLE_REGISTRY_INVALID_ORACLE
        );

        // Set the configuration for the asset oracle.
        assetToOracle_[asset] = OracleConfiguration({
            validPriceDuration: validPriceDuration,
            oracle: oracle
        });

        // Add the asset to the set of registered assets if it is not already registered.
        registeredAssets_.add(address(asset));

        emit AssetOracleRegistered(asset, oracle, validPriceDuration);
    }

    /**
     * @notice Remove the oracle for an asset, preventing prices for the oracle `asset` from being fetched.
     * @dev Emits the `AssetOracleRemoved()` event.
     * @param asset The asset to remove from the oracle registry.
     */
    function _removeAssetOracle(address asset) internal {
        // Don't do anything if the asset is not registered.
        if (!registeredAssets_.contains(asset)) {
            return;
        }

        // Remove the asset from the set of registered assets.
        registeredAssets_.remove(asset);

        // Delete the asset's oracle configuration.
        delete assetToOracle_[asset];

        emit AssetOracleRemoved(asset);
    }

    /**
     * @notice Get the price for an asset.
     * @param asset     The asset to fetch the price for. Must have a valid oracle, and the oracle's last update must be within the valid price duration.
     * @return price    The price for the asset with `decimals` amount of precision.
     * @return decimals The amount of decimals used by the oracle to represent the price of the asset / asset pair.
     */
    function _getAssetPrice(
        address asset
    ) internal view returns (uint256 price, uint256 decimals) {
        // Get the registered oracle for the asset, if it exists.
        OracleConfiguration memory oracleConfig = assetToOracle_[asset];

        // Make sure the oracle for this asset exists.
        require(
            oracleConfig.oracle != IChainlinkAggregatorV3(address(0)),
            ChainlinkErrors.ORACLE_REGISTRY_ASSET_NOT_FOUND
        );

        // Get the latest round data, which includes the price and the timestamp of the last oracle price update.
        // The timestamp is used to validate that the price is not stale.
        (, int256 oraclePrice, , uint256 timestamp, ) = oracleConfig
            .oracle
            .latestRoundData();

        // Prices that are less than or equal to zero should be considered invalid.
        require(
            oraclePrice > 0,
            ChainlinkErrors.ORACLE_REGISTRY_INVALID_ORACLE_PRICE
        );

        // Make sure the price is within the valid price duration.
        // This is an important step in retrieving the price, as it ensures that old oracle prices do not result in
        // inintended behavior / unfair asset pricing.
        require(
            block.timestamp - timestamp <= oracleConfig.validPriceDuration,
            ChainlinkErrors
                .ORACLE_REGISTRY_LAST_UPDATE_TIMESTAMP_EXCEEDS_VALID_TIMESTAMP_RANGE
        );

        return (
            SafeCast.toUint256(oraclePrice),
            oracleConfig.oracle.decimals()
        );
    }
}

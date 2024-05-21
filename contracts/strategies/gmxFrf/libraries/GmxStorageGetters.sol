// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Keys } from "../../../lib/gmx/keys/Keys.sol";
import { IGmxV2DataStore } from "../interfaces/gmx/IGmxV2DataStore.sol";

/**
 * @title GmxStorageGetters
 * @author GoldLink
 *
 * @dev Library for getting values directly from Gmx's `datastore` contract.
 */
library GmxStorageGetters {
    // ============ Internal Functions ============

    /**
     * @notice Get claimable collateral time divisor.
     * @param dataStore                       The data store the time divisor in in.
     * @return claimableCollateralTimeDivisor The time divisor for calculating the initial claim timestamp.
     */
    function getClaimableCollateralTimeDivisor(
        IGmxV2DataStore dataStore
    ) internal view returns (uint256 claimableCollateralTimeDivisor) {
        return dataStore.getUint(Keys.CLAIMABLE_COLLATERAL_TIME_DIVISOR);
    }

    /**
     * @notice Get account claimable collateral.
     * @param dataStore            The data store the claimable collateral is registered in.
     * @param market               The market the claimable collateral is for.
     * @param token                The token associated with the account's claimable collateral.
     * @param timeKey              The time key for the claimable collateral.
     * @param account              The account that has claimable collateral.
     * @return claimableCollateral The claimable collateral an account has for a market.
     */
    function getAccountClaimableCollateral(
        IGmxV2DataStore dataStore,
        address market,
        address token,
        uint256 timeKey,
        address account
    ) internal view returns (uint256 claimableCollateral) {
        bytes32 key = Keys.claimableCollateralAmountKey(
            market,
            token,
            timeKey,
            account
        );

        return dataStore.getUint(key);
    }

    /**
     * @notice Get claimable funding fees.
     * @param token                 The token associated with the account's claimable funding fees.
     * @param market                The market the claimable funding fees are for.
     * @param account               The account that has claimable funding fees.
     * @return claimableFundingFees The claimable funding fees an account has for a market.
     */
    function getClaimableFundingFees(
        IGmxV2DataStore dataStore,
        address market,
        address token,
        address account
    ) internal view returns (uint256 claimableFundingFees) {
        bytes32 key = Keys.claimableFundingAmountKey(market, token, account);

        return dataStore.getUint(key);
    }

    /**
     * @notice Get saved callback contract an account has for a market.
     * @param dataStore              The data store the saved callback contractl is in.
     * @param market                 The market the saved callback contract is for.
     * @param account                The account that has the saved callback contract.
     * @return savedCallbackContract The address of the saved callback contract.
     */
    function getSavedCallbackContract(
        IGmxV2DataStore dataStore,
        address account,
        address market
    ) internal view returns (address savedCallbackContract) {
        bytes32 key = Keys.savedCallbackContract(account, market);

        return dataStore.getAddress(key);
    }
}

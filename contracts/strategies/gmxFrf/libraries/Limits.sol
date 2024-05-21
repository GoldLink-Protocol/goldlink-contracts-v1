// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Constants } from "../../../libraries/Constants.sol";

/**
 * @title Limits
 * @author GoldLink
 *
 * @dev Constants library for limiting manager configuration variables to prevent owner manipulation.
 */
library Limits {
    /// ================= Constants ====================

    // Oracle Limits
    uint256 internal constant MAX_REGISTERED_ASSET_COUNT = 30;

    // Market Limits
    uint256 internal constant MAX_MARKET_COUNT = 30;

    // Order Pricing Parameters Limits
    uint256 internal constant MINIMUM_MAX_SWAP_SLIPPAGE_PERCENT = 0.02e18; // 2%
    uint256 internal constant MINIMUM_MAX_POSITION_SLIPPAGE_PERCENT = 0.02e18; // 2%

    // Unwind Parameters Limits
    uint256 internal constant MINIMUM_MAX_DELTA_PROPORTION_PERCENT = 1.025e18; // 102.5%
    uint256 internal constant MINIMUM_MAX_POSITION_LEVERAGE_PERCENT = 1.05e18; // 105%
    uint256 internal constant MAXIMUM_UNWIND_FEE_PERCENT = 0.1e18; // 10%

    // Shared Order Limits
    uint256 internal constant MAXIMUM_CALLBACK_GAS_LIMIT = 2e6; // 2 million gwei
    uint256 internal constant MAXIMUM_EXECUTION_FEE_BUFFER_PERCENT = 0.2e18; // 20%
    uint256 internal constant MAXIMUM_ASSET_LIQUIDATION_FEE_PERCENT = 0.1e18; // 10%
    uint256 internal constant MINIMUM_WITHDRAWAL_BUFFER_PERCENT = 1e18; // 100%
}

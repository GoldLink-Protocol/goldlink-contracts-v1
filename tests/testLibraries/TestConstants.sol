// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import {
    IStrategyReserve
} from "../../contracts/interfaces/IStrategyReserve.sol";
import {
    IInterestRateModel
} from "../../contracts/interfaces/IInterestRateModel.sol";

library TestConstants {
    //
    // Addresses
    //
    address public constant FOURTH_ADDRESS =
        0xC6363973F4AdEc287A5C01E6d331894b622bd535;
    address public constant SECOND_ADDRESS =
        0xDFE888db0f3419fCDa362772D8bE9E52Aa061069;
    address public constant THIRD_ADDRESS =
        0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD;
    address public constant ZERO_ADDRESS = address(0);
    address public constant DUMP_ADDRESS = address(1);

    //
    // Token Balances
    //
    uint256 public constant ONE_HUNDRED_USDC = 1e8;

    //
    // uint256
    //
    uint256 public constant ONE_THOUSAND = 1000;

    //
    // Strategy Bank Parameters
    //
    uint256 public constant DEFAULT_MINIMUM_OPEN_HEALTH_SCORE = 0.5e18; // 50%
    uint256 public constant DEFAULT_LIQUIDATABLE_HEALTH_SCORE = 0.25e18; // 25%
    uint256 public constant DEFAULT_EXECUTOR_PREMIUM = 0.0075e18; // 0.75%
    uint256 public constant DEFAULT_INSURANCE_PREMIUM = 0.05e18; // 5%
    uint256 public constant DEFAULT_LIQUIDATION_INSURANCE_PREMIUM = 0.0575e18; // 5.75%
    uint256 public constant MINIMUM_COLLATERAL_BALANCE = 2;

    //
    // Reserve Parameters
    //
    uint256 public constant DEFAULT_TVL_CAP = 1e18;
    uint256 public constant DEFAULT_OPTIMAL_UTILIZATION = 0.5e18; // 50%
    uint256 public constant DEFAULT_BASE_INTEREST_RATE = 0.05e18; // 5%
    uint256 public constant DEFAULT_RATE_SLOPE_1 = 0.1e18; // 10%
    uint256 public constant DEFAULT_RATE_SLOPE_2 = 0.2e18; // 20%
    uint256 public constant MINIMUM_LENDER_EXPOSURE_BALANCE = 10;

    //
    // Errors
    //
    bytes public constant ERC20_ZERO_ADDRESS_ERROR_BYTES =
        hex"ec442f050000000000000000000000000000000000000000000000000000000000000000";

    function defaultReserveParameters()
        public
        pure
        returns (IStrategyReserve.ReserveParameters memory)
    {
        return
            IStrategyReserve.ReserveParameters(
                DEFAULT_TVL_CAP,
                IInterestRateModel.InterestRateModelParameters(
                    DEFAULT_OPTIMAL_UTILIZATION,
                    DEFAULT_BASE_INTEREST_RATE,
                    DEFAULT_RATE_SLOPE_1,
                    DEFAULT_RATE_SLOPE_2
                ),
                "MOCK TOKEN FOR GOLDLINK",
                "MGLK"
            );
    }
}

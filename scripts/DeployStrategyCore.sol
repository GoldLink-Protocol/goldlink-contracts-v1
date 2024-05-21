// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StrategyController } from "../contracts/core/StrategyController.sol";
import { IStrategyBank } from "../contracts/interfaces/IStrategyBank.sol";
import { IStrategyReserve } from "../contracts/interfaces/IStrategyReserve.sol";
import {
    IInterestRateModel
} from "../contracts/interfaces/IInterestRateModel.sol";
import {
    IStrategyAccountDeployer
} from "../contracts/interfaces/IStrategyAccountDeployer.sol";

contract DeployStrategyCore is Script {
    /// @notice The private key for the deployer account.
    string constant DEPLOYER_PRIVATE_KEY_ENV_KEY = "DEPLOYER_PRIVATE_KEY";

    /// @notice The `owner` of the strategy.
    string constant STRATEGY_OWNER_ENV_KEY = "STRATEGY_OWNER";
    /// @notice The token used for borrow/lend accounting for the strategy.
    string constant STRATEGY_ASSET_ENV_KEY = "STRATEGY_ASSET";
    /// @notice The TVL cap, denominated in the `STRATEGY ASSET`, that denominates the maximum borrow/lend capacity for the strategy.
    string constant TOTAL_VALUE_LOCKED_CAP_ENV_KEY = "TOTAL_VALUE_LOCKED_CAP";
    /// @notice The name of the reserve's ERC20 lender shares.
    string constant ERC20_NAME_ENV_KEY = "ERC20_NAME";
    /// @notice The symbol of the reserve's ERC20 lender shares.
    string constant ERC20_SYMBOL_ENV_KEY = "ERC20_SYMBOL";
    /// @notice The optimal utilization for the reserve's interest rate model.
    string constant OPTIMAL_UTILIZATION_ENV_KEY = "OPTIMAL_UTILIZATION";
    /// @notice The base interest rate for the reserve's interest rate model.
    string constant BASE_INTEREST_RATE_ENV_KEY = "BASE_INTEREST_RATE";
    /// @notice The reserve's interest rate curve slope when utilization is below optimal.
    string constant RATE_SLOPE_1_ENV_KEY = "RATE_SLOPE_1";
    /// @notice The reserve's interest rate curve slope when utilization is above optimal.
    string constant RATE_SLOPE_2_ENV_KEY = "RATE_SLOPE_2";
    /// @notice The bank's minimum health score an account can open a loan with.
    string constant MINIMUM_OPEN_HEALTH_SCORE_ENV_KEY =
        "MINIMUM_OPEN_HEALTH_SCORE";
    /// @notice The bank's liquidatable health score that accounts can be liquidated when below.
    string constant LIQUIDATABLE_HEALTH_SCORE_ENV_KEY =
        "LIQUIDATABLE_HEALTH_SCORE";
    /// @notice The premium percentage paid to the executor of a liquidation by the bank.
    string constant EXECUTOR_PREMIUM_ENV_KEY = "EXECUTOR_PREMIUM";
    /// @notice The percentage of interest that is dedicated to the bank's insurance.
    string constant INSURANCE_PREMIUM_ENV_KEY = "INSURANCE_PREMIUM";
    /// @notice The percentage of assets remaining after liquidation that are added to the bank's insurance.
    string constant LIQUIDATION_INSURANCE_PREMIUM_ENV_KEY =
        "LIQUIDATION_INSURANCE_PREMIUM";
    /// @notice The minimum balance of collateral that an account can have, denominated in `STRATEGY_ASSET`.
    string constant MINIMUM_COLLATERAL_BALANCE_ENV_KEY =
        "MINIMUM_COLLATERAL_BALANCE";
    /// @notice The contract that deploy's accounts for this strategy.
    string constant STRATEGY_ACCOUNT_DEPLOYER_ENV_KEY =
        "STRATEGY_ACCOUNT_DEPLOYER";

    function setup() public {}

    /*
        Deployment Steps:
        1) Get environment variables to populate parameters.
        2) Deploy Strategy Controller with parameters.
    */
    function run() public {
        address strategyOwner = vm.envAddress(STRATEGY_OWNER_ENV_KEY);
        IERC20 strategyAsset = IERC20(vm.envAddress(STRATEGY_ASSET_ENV_KEY));
        uint256 privateKey = vm.envUint(DEPLOYER_PRIVATE_KEY_ENV_KEY);
        IStrategyReserve.ReserveParameters
            memory reserveParams = _getReserveParameters();

        IStrategyBank.BankParameters memory bankParams = _getBankParameters();

        vm.startBroadcast(privateKey);
        StrategyController controller = new StrategyController(
            strategyOwner,
            strategyAsset,
            reserveParams,
            bankParams
        );
        vm.stopBroadcast();

        console.log("Controller:", address(controller));
        console.log("Reserve:", address(controller.STRATEGY_RESERVE()));
        console.log("Bank:", address(controller.STRATEGY_BANK()));
    }

    function _getReserveParameters()
        internal
        view
        returns (IStrategyReserve.ReserveParameters memory params)
    {
        params.totalValueLockedCap = vm.envUint(TOTAL_VALUE_LOCKED_CAP_ENV_KEY);
        params.interestRateModel = _getInterestRateModelParameters();
        params.erc20Name = vm.envString(ERC20_NAME_ENV_KEY);
        params.erc20Symbol = vm.envString(ERC20_SYMBOL_ENV_KEY);
    }

    function _getInterestRateModelParameters()
        internal
        view
        returns (IInterestRateModel.InterestRateModelParameters memory params)
    {
        params.baseInterestRate = vm.envUint(BASE_INTEREST_RATE_ENV_KEY);
        params.optimalUtilization = vm.envUint(OPTIMAL_UTILIZATION_ENV_KEY);
        params.rateSlope1 = vm.envUint(RATE_SLOPE_1_ENV_KEY);
        params.rateSlope2 = vm.envUint(RATE_SLOPE_2_ENV_KEY);
    }

    function _getBankParameters()
        internal
        view
        returns (IStrategyBank.BankParameters memory params)
    {
        params.minimumOpenHealthScore = vm.envUint(
            MINIMUM_OPEN_HEALTH_SCORE_ENV_KEY
        );
        params.liquidatableHealthScore = vm.envUint(
            LIQUIDATABLE_HEALTH_SCORE_ENV_KEY
        );
        params.executorPremium = vm.envUint(EXECUTOR_PREMIUM_ENV_KEY);
        params.insurancePremium = vm.envUint(INSURANCE_PREMIUM_ENV_KEY);
        params.liquidationInsurancePremium = vm.envUint(
            LIQUIDATION_INSURANCE_PREMIUM_ENV_KEY
        );
        params.minimumCollateralBalance = vm.envUint(
            MINIMUM_COLLATERAL_BALANCE_ENV_KEY
        );
        params.strategyAccountDeployer = IStrategyAccountDeployer(
            vm.envAddress(STRATEGY_ACCOUNT_DEPLOYER_ENV_KEY)
        );
    }
}

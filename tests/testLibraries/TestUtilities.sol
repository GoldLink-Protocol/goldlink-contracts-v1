// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { GoldLinkERC20Mock } from "../mocks/GoldLinkERC20Mock.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Constants } from "../../contracts/libraries/Constants.sol";
import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import { TestConstants } from "./TestConstants.sol";
import {
    IStrategyAccountDeployer
} from "../../contracts/interfaces/IStrategyAccountDeployer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IStrategyAccount
} from "../../contracts/interfaces/IStrategyAccount.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    StrategyAccountDeployerMock
} from "../mocks/StrategyAccountDeployerMock.sol";

library TestUtilities {
    using Math for uint256;
    using SafeERC20 for IERC20;

    function mintAndApprove(
        GoldLinkERC20Mock erc20,
        uint256 mintAmount,
        address approvee
    ) internal {
        erc20.mint(address(this), mintAmount);
        erc20.approve(approvee, type(uint256).max);
    }

    function mintTo(
        GoldLinkERC20Mock erc20,
        uint256 mintAmount,
        address to
    ) internal {
        erc20.mint(to, mintAmount);
    }

    function defaultBankParameters(
        IStrategyAccountDeployer strategyDeployer
    ) internal pure returns (IStrategyBank.BankParameters memory) {
        return
            IStrategyBank.BankParameters({
                minimumOpenHealthScore: TestConstants
                    .DEFAULT_MINIMUM_OPEN_HEALTH_SCORE,
                liquidatableHealthScore: TestConstants
                    .DEFAULT_LIQUIDATABLE_HEALTH_SCORE,
                executorPremium: TestConstants.DEFAULT_EXECUTOR_PREMIUM,
                insurancePremium: TestConstants.DEFAULT_INSURANCE_PREMIUM,
                liquidationInsurancePremium: TestConstants
                    .DEFAULT_LIQUIDATION_INSURANCE_PREMIUM,
                minimumCollateralBalance: TestConstants
                    .MINIMUM_COLLATERAL_BALANCE,
                strategyAccountDeployer: strategyDeployer
            });
    }

    function getInsuranceFund(
        IStrategyBank strategyBank,
        IERC20 erc20
    ) internal view returns (uint256 insuranceFund) {
        uint256 totalBalance = erc20.balanceOf(address(strategyBank));

        uint256 totalCollateral = strategyBank.totalCollateral_();

        if (totalBalance > totalCollateral) {
            return totalBalance - totalCollateral;
        }
    }

    // TODO fix
    function defaultStrategyDeployer()
        internal
        returns (StrategyAccountDeployerMock)
    {
        return new StrategyAccountDeployerMock();
    }

    /**
     * @notice Implements max fuzz value, setting the maximum that the fuzz
     * value can be.
     */
    function maxFuzzValue(
        uint256 fuzzValue,
        uint256 max,
        bool allowZero
    ) internal pure returns (uint256 newValue) {
        newValue = fuzzValue;

        if (fuzzValue == 0 && !allowZero) newValue++;
        return Math.min(max, newValue);
    }

    function compareAddressArrays(
        address[] memory array1,
        address[] memory array2
    ) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked((array1))) ==
            keccak256(abi.encodePacked((array2)));
    }

    function compareUint256Arrays(
        uint256[] memory array1,
        uint256[] memory array2
    ) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked((array1))) ==
            keccak256(abi.encodePacked((array2)));
    }
}

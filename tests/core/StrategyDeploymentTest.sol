// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {
    StrategyController
} from "../../contracts/core/StrategyController.sol";

import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import { TestConstants } from "../testLibraries/TestConstants.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TestUtilities } from "../testLibraries/TestUtilities.sol";
import { GoldLinkERC20Mock } from "../mocks/GoldLinkERC20Mock.sol";
import { StrategyBank } from "../../contracts/core/StrategyBank.sol";
import { ProtocolDeployer } from "../ProtocolDeployer.sol";
import { Errors } from "../../contracts/libraries/Errors.sol";
import {
    IStrategyReserve
} from "../../contracts/interfaces/IStrategyReserve.sol";
import {
    IStrategyAccountDeployer
} from "../../contracts/interfaces/IStrategyAccountDeployer.sol";
import {
    StrategyAccountDeployerMock
} from "../mocks/StrategyAccountDeployerMock.sol";
import {
    IStrategyController
} from "../../contracts/core/StrategyController.sol";

contract StrategyDeploymentTest is Test, ProtocolDeployer {
    // ============ Storage Variables ============

    IStrategyBank.BankParameters bankParameters;
    IStrategyReserve.ReserveParameters reserveParameters;

    // ============ Constructor ============

    constructor() ProtocolDeployer(false) {}

    // ============ Setup ============

    function setUp() public {
        StrategyAccountDeployerMock deployer = new StrategyAccountDeployerMock();

        bankParameters = TestUtilities.defaultBankParameters(
            IStrategyAccountDeployer(address(deployer))
        );
        reserveParameters = TestConstants.defaultReserveParameters();
    }

    // ============ Create Strategy Tests ============

    function testCreateStrategyZeroMinimumOpenHealthScore() public {
        bankParameters.minimumOpenHealthScore = 0;

        _expectRevert(
            Errors
                .STRATEGY_BANK_MINIMUM_OPEN_HEALTH_SCORE_CANNOT_BE_AT_OR_BELOW_LIQUIDATABLE_HEALTH_SCORE
        );
        new StrategyController(
            address(this),
            usdc,
            reserveParameters,
            bankParameters
        );
    }

    function testCreateStrategyHealthScoresInverted() public {
        bankParameters.minimumOpenHealthScore =
            bankParameters.liquidatableHealthScore -
            1;

        _expectRevert(
            Errors
                .STRATEGY_BANK_MINIMUM_OPEN_HEALTH_SCORE_CANNOT_BE_AT_OR_BELOW_LIQUIDATABLE_HEALTH_SCORE
        );
        new StrategyController(
            address(this),
            usdc,
            reserveParameters,
            bankParameters
        );
    }

    function testCreateStrategy() public {
        (
            IStrategyReserve reserve,
            IStrategyBank strategyBank,

        ) = _createStrategy(usdc, bankParameters, reserveParameters);

        assertNotEq(address(reserve), TestConstants.ZERO_ADDRESS);
        assertEq(
            address(strategyBank.STRATEGY_ACCOUNT_DEPLOYER()),
            address(bankParameters.strategyAccountDeployer)
        );
    }

    function testCreateStrategyZeroTotalValueLockedCap() public {
        reserveParameters.totalValueLockedCap = 0;
        (
            IStrategyReserve reserve,
            IStrategyBank strategyBank,

        ) = _createStrategy(usdc, bankParameters, reserveParameters);

        assertNotEq(address(reserve), TestConstants.ZERO_ADDRESS);
        assertEq(
            address(strategyBank.STRATEGY_ACCOUNT_DEPLOYER()),
            address(bankParameters.strategyAccountDeployer)
        );
    }

    function _expectRevert(string memory revertMsg) internal {
        vm.expectRevert(bytes(revertMsg));
    }
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { TestUtilities } from "../testLibraries/TestUtilities.sol";
import { TestConstants } from "../testLibraries/TestConstants.sol";
import {
    IStrategyAccount
} from "../../contracts/interfaces/IStrategyAccount.sol";
import { StrategyAccountMock } from "../mocks/StrategyAccountMock.sol";
import { StrategyReserve } from "../../contracts/core/StrategyReserve.sol";
import {
    IStrategyAccount
} from "../../contracts/interfaces/IStrategyAccount.sol";
import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import {
    IStrategyController
} from "../../contracts/interfaces/IStrategyController.sol";
import {
    IStrategyReserve
} from "../../contracts/interfaces/IStrategyReserve.sol";
import "forge-std/Test.sol";

import { ProtocolDeployer } from "../ProtocolDeployer.sol";

contract ReentrantTest is Test, ProtocolDeployer {
    IStrategyReserve reserve;
    IStrategyBank bank;
    IStrategyController controller;
    IStrategyAccount account;

    constructor() ProtocolDeployer(true) {}

    function setUp() external {
        (reserve, bank, controller, account) = _createDefaultStrategy(fakeusdc);
    }

    function testReentrant() public {
        TestUtilities.mintAndApprove(fakeusdc, 1000, address(reserve));
        TestUtilities.mintAndApprove(fakeusdc, 1000, address(account));
        TestUtilities.mintAndApprove(fakeusdc, 1000, address(bank));

        IStrategyAccount sa = account;

        TestUtilities.mintAndApprove(fakeusdc, 1000000, address(this));

        fakeusdc.flipNormal();
        reserve.deposit(10000, address(this));
        sa.executeAddCollateral(5000);
        sa.executeBorrow(100);
        reserve.deposit(1, address(this));
        fakeusdc.flipNormal();

        vm.expectRevert("StrategyController: Lock already acquired.");
        reserve.deposit(100, address(this));
        vm.expectRevert("StrategyController: Lock already acquired.");
        reserve.mint(100, address(this));

        vm.expectRevert("StrategyController: Lock already acquired.");
        reserve.withdraw(1, address(this), address(this));
        vm.expectRevert("StrategyController: Lock already acquired.");
        reserve.redeem(1, address(this), address(this));

        vm.expectRevert("StrategyController: Lock already acquired.");
        sa.executeAddCollateral(50);

        vm.expectRevert("StrategyController: Lock already acquired.");
        sa.executeBorrow(100);

        vm.expectRevert("StrategyController: Lock already acquired.");
        sa.executeRepayLoan(1);

        vm.expectRevert("StrategyController: Lock already acquired.");
        sa.executeWithdrawCollateral(
            address(this),
            TestConstants.MINIMUM_COLLATERAL_BALANCE,
            false
        );

        vm.warp(2000000 days);

        sa.executeInitiateLiquidation();
        vm.expectRevert("StrategyController: Lock already acquired.");
        sa.executeProcessLiquidation();
    }
}

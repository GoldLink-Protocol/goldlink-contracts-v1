// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { TestUtilities } from "../testLibraries/TestUtilities.sol";
import { TestConstants } from "../testLibraries/TestConstants.sol";
import {
    IStrategyAccount
} from "../../contracts/interfaces/IStrategyAccount.sol";
import { StrategyAccountMock } from "../mocks/StrategyAccountMock.sol";
import "forge-std/Test.sol";

import { ProtocolDeployer } from "../ProtocolDeployer.sol";

// Please prefix all tests with `testGas`.
contract GasTest is Test, ProtocolDeployer {
    IStrategyAccount liquidatableAccount;
    IStrategyAccount repayableAccount;
    IStrategyAccount withdrawableAccount;

    // Provide everything necessary to eval each basic call.
    function setUp() public {
        liquidatableAccount = strategyAccounts[0];
        repayableAccount = IStrategyAccount(
            strategyBanks[0].executeOpenAccount(address(this))
        );
        withdrawableAccount = IStrategyAccount(
            strategyBanks[0].executeOpenAccount(address(this))
        );

        TestUtilities.mintAndApprove(usdc, 1000, address(strategyReserves[0]));
        TestUtilities.mintAndApprove(usdc, 1000, address(liquidatableAccount));
        TestUtilities.mintAndApprove(usdc, 1000, address(repayableAccount));
        TestUtilities.mintAndApprove(usdc, 1000, address(withdrawableAccount));
        TestUtilities.mintAndApprove(usdc, 1000, address(strategyBanks[0]));

        strategyReserves[0].deposit(100, address(this));
        strategyReserves[0].mint(100, address(this));

        strategyReserves[0].withdraw(1, msg.sender, address(this));
        strategyReserves[0].redeem(1, msg.sender, address(this));

        liquidatableAccount.executeAddCollateral(50);
        liquidatableAccount.executeBorrow(100);

        vm.warp(6075 days);

        repayableAccount.executeAddCollateral(50);
        repayableAccount.executeBorrow(90);

        withdrawableAccount.executeAddCollateral(50);
    }

    constructor() ProtocolDeployer(false) {}

    function testGasDeposit() public {
        strategyReserves[0].deposit(100, msg.sender);
    }

    function testGasMint() public {
        strategyReserves[0].mint(1, msg.sender);
    }

    function testGasWithdraw() public {
        strategyReserves[0].withdraw(1, msg.sender, address(this));
    }

    function testGasRedeem() public {
        strategyReserves[0].redeem(1, msg.sender, address(this));
    }

    function testGasExecuteAddCollateral() public {
        liquidatableAccount.executeAddCollateral(50);
    }

    function testGasExecuteBorrow() public {
        repayableAccount.executeBorrow(5);
    }

    function testGasExecuteRepay() public {
        repayableAccount.executeRepayLoan(50);
    }

    function testGasExecuteWithdraw() public {
        withdrawableAccount.executeWithdrawCollateral(address(this), 50, false);
    }

    function testGasExecuteWithdrawSoft() public {
        repayableAccount.executeWithdrawCollateral(address(this), 50, true);
    }
}

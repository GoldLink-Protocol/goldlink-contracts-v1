// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { TestUtilities } from "../testLibraries/TestUtilities.sol";
import { TestConstants } from "../testLibraries/TestConstants.sol";
import { StrategyAccountMock } from "../mocks/StrategyAccountMock.sol";
import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import {
    StrategyBankHelpers
} from "../../contracts/libraries/StrategyBankHelpers.sol";
import { PercentMath } from "../../contracts/libraries/PercentMath.sol";
import { StrategyReserve } from "../../contracts/core/StrategyReserve.sol";
import {
    IStrategyAccount
} from "../../contracts/interfaces/IStrategyAccount.sol";
import { StrategyBank } from "../../contracts/core/StrategyBank.sol";
import "forge-std/Test.sol";

import { InvariantHandler } from "./InvariantHandler.sol";

contract InvariantTest is StdInvariant, Test {
    using PercentMath for uint256;
    using StrategyBankHelpers for IStrategyBank.StrategyAccountHoldings;

    InvariantHandler handler;

    address[] accounts;

    // ============ Setup ============

    function setUp() public {
        // True if we want to skip validations - good for accelerating tests
        // but decreases coverage.
        handler = new InvariantHandler(false);

        // Only target the handler.
        targetContract(address(handler));

        // Add senders.
        addAccount(address(this));
        addAccount(address(handler));
        addAccount(TestConstants.SECOND_ADDRESS);
        addAccount(TestConstants.THIRD_ADDRESS);
        addAccount(TestConstants.FOURTH_ADDRESS);

        console.log("This address: ", address(this));
        console.log("Handler address: ", address(handler));

        // Setup multiple Strategy Accounts for every reserve for every target sender.
        address[] memory senders = targetSenders();
        for (uint256 i = 0; i < senders.length; i++) {
            for (uint256 j = 0; j < 4; j++) {
                for (uint256 x = 0; x < 3; x++) {
                    handler.addAccount(uint16(j), senders[i]);
                }
            }
        }

        // specify specific calls to debug.
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.warp.selector;
        selectors[1] = handler.createLender.selector;
        selectors[2] = handler.increasePositionDeposit.selector;
        selectors[3] = handler.increasePositionMint.selector;
        selectors[4] = handler.decreasePositionWithdraw.selector;
        selectors[5] = handler.decreasePositionRedeem.selector;
        selectors[6] = handler.addCollateral.selector;
        selectors[7] = handler.borrow.selector;
        selectors[8] = handler.repayLoan.selector;
        selectors[9] = handler.withdrawCollateral.selector;
        selectors[10] = handler.simulateProfitOrLoss.selector;

        targetSelector(
            FuzzSelector({ addr: address(handler), selectors: selectors })
        );
    }

    // ============ Public Functions ============

    function invariantEmpty() public {
        // for testing if `InvariantHandler` works.
    }

    // Walk through all state-changing functions in handler and make sure they
    // work given some random prior calls.
    function invariantGeneralTest() public {
        handler.warp(10);

        uint256 shares = handler.createLender(1, 100);

        handler.createLender(2, 100);

        shares += handler.increasePositionDeposit(1, 50);
        handler.increasePositionMint(2, 100);

        handler.decreasePositionWithdraw(2, 100);
        handler.decreasePositionRedeem(1, uint16(shares));

        handler.addCollateral(0, 100);

        handler.simulateProfitOrLoss(0, 50, true);
        handler.simulateProfitOrLoss(0, 70, false);

        handler.borrow(0, 200);

        handler.repayLoan(0, 100);
        handler.repayLoan(0, 50);

        handler.withdrawCollateral(0, 50, false);
        handler.withdrawCollateral(0, 100, true);
    }

    // Remove all funds from the protocol given some random prior calls and verify all balances.
    function invariantRemoveAllLoanAssetsTest() public {
        vm.warp(10 days);

        // Iterate all strategy accounts.
        StrategyAccountMock[] memory strategyAccounts = handler
            .getAllStrategyAccounts();
        for (uint256 i = 0; i < strategyAccounts.length; i++) {
            StrategyAccountMock account = strategyAccounts[i];
            StrategyBank strategyBank = StrategyBank(
                address(handler.getStrategyBank(account))
            );

            IStrategyBank.StrategyAccountHoldings memory holdings = strategyBank
                .getStrategyAccountHoldings(address(account));

            // Simple health factor repair.
            if (holdings.loan > 0) {
                TestUtilities.mintAndApprove(
                    handler.usdc(),
                    holdings.loan * 2,
                    address(strategyBank)
                );
                account.executeAddCollateral(holdings.loan * 2);
            }

            // Refresh holdings.
            vm.prank(account.getOwner());
            account.executeBorrow(0);
            holdings = strategyBank.getStrategyAccountHoldings(
                address(account)
            );

            // Get old assets.
            uint256 oldAssets = handler.usdc().balanceOf(
                address(strategyBank.STRATEGY_RESERVE())
            );

            // Repay.
            if (holdings.loan > 0) {
                vm.startPrank(account.getOwner());
                account.executeRepayLoan(holdings.loan);
                vm.stopPrank();
            }

            // Refresh holdings and withdraw.
            uint256 collateral = strategyBank
                .getStrategyAccountHoldingsAfterPayingInterest(address(account))
                .collateral;

            vm.startPrank(account.getOwner());
            account.executeWithdrawCollateral(
                account.getOwner(),
                collateral,
                true
            );
            vm.stopPrank();

            // Expect account collateral to be zeroed out.
            assertEq(
                strategyBank
                    .getStrategyAccountHoldingsAfterPayingInterest(
                        address(account)
                    )
                    .collateral,
                0
            );

            // Verify change in reserve funds results in expected balance.
            assertEq(
                handler.usdc().balanceOf(
                    address(strategyBank.STRATEGY_RESERVE())
                ),
                oldAssets + holdings.loan,
                "RS balance != expected."
            );
        }

        // Remove all funds from the reserve.
        for (uint256 i = 0; i < accounts.length; i++) {
            for (uint256 j = 0; j < handler.STRATEGY_COUNT(); j++) {
                vm.startPrank(accounts[i]);
                handler.strategyReserves(j).redeem(
                    handler.strategyReserves(j).balanceOf(accounts[i]),
                    accounts[i],
                    accounts[i]
                );
                vm.stopPrank();
            }
        }

        for (uint256 i = 0; i < handler.STRATEGY_COUNT(); i++) {
            // Ensure strategy reserves were removed.
            assertLe(
                handler.usdc().balanceOf(address(handler.strategyReserves(i))),
                10,
                "Not all SR assets removed"
            );

            // Verify that all collateral was removed.
            // Due to rounding, it is possible in this test that for each strategy account
            // there was a unit of collateral left behind.
            assertLe(
                handler.strategyReserves(i).STRATEGY_BANK().totalCollateral_(),
                strategyAccounts.length,
                "Total collateral not zero'd out."
            );
        }
    }

    // ============ Internal Functions ============

    function addAccount(address account) internal {
        targetSender(account);
        accounts.push(account);
    }
}

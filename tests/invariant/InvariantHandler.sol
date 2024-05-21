// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { StateManager } from "../StateManager.sol";
import { TestUtilities } from "../testLibraries/TestUtilities.sol";
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    IStrategyAccount
} from "../../contracts/interfaces/IStrategyAccount.sol";
import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import { StrategyAccountMock } from "../mocks/StrategyAccountMock.sol";
import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import {
    StrategyBankHelpers
} from "../../contracts/libraries/StrategyBankHelpers.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { TestConstants } from "../testLibraries/TestConstants.sol";
import {
    IStrategyReserve
} from "../../contracts/interfaces/IStrategyReserve.sol";
import { StrategyBank } from "../../contracts/core/StrategyBank.sol";

import "forge-std/Test.sol";

contract InvariantHandler is StateManager {
    using StrategyBankHelpers for IStrategyBank.StrategyAccountHoldings;
    using Math for uint256;

    // ============ Storage Variables ============

    mapping(address => uint256[]) private _tokenMapping;
    mapping(address => uint256[]) private _strategyAccountIndexMapping;

    // Can contain zero amount as values are never unset.
    mapping(uint256 => EnumerableSet.UintSet) private _lenderExposures;

    EnumerableSet.AddressSet validOwners;

    // ============ Constructor ============

    constructor(bool skipValidations) StateManager(skipValidations) {
        for (uint256 i = 0; i < strategyAccounts.length; i++) {
            _strategyAccountIndexMapping[address(this)].push(i);
        }

        // Only addresses able to own new accounts.
        EnumerableSet.add(validOwners, msg.sender);
        EnumerableSet.add(validOwners, address(this));
        EnumerableSet.add(validOwners, TestConstants.SECOND_ADDRESS);
        EnumerableSet.add(validOwners, TestConstants.THIRD_ADDRESS);
        EnumerableSet.add(validOwners, TestConstants.FOURTH_ADDRESS);
    }

    // ============ External Functions ============

    // General.

    function warp(uint32 warpTime) external {
        // Warp cannot be greater than a day.
        warpTime %= 86400;
        vm.warp(warpTime + 1);
    }

    // Reserves Manager.

    function createLender(
        uint24 id,
        uint16 amount
    ) external returns (uint256 shares) {
        amount = uint16(
            Math.max(amount, TestConstants.MINIMUM_LENDER_EXPOSURE_BALANCE)
        );

        id %= 4;

        // Update state for PNL
        _refreshState(id);

        // Return early if already exists.
        if (strategyReserves[id].balanceOf(msg.sender) > 0) {
            return 0;
        }

        shares = strategyReserves[id].previewDeposit(amount);

        vm.prank(msg.sender);
        _createLender(id, amount, shares);

        return shares;
    }

    function increasePositionDeposit(
        uint16 id,
        uint16 amount
    ) external returns (uint256 shares) {
        amount = uint16(
            Math.max(amount, TestConstants.MINIMUM_LENDER_EXPOSURE_BALANCE)
        );

        id %= 4;

        // Update state for PNL
        _refreshState(id);

        shares = strategyReserves[id].previewDeposit(amount);

        vm.prank(msg.sender);
        _increasePosition(id, amount, shares);

        return shares;
    }

    function increasePositionMint(uint16 id, uint16 shares) external {
        shares = uint16(
            Math.max(shares, TestConstants.MINIMUM_LENDER_EXPOSURE_BALANCE)
        );

        id %= 4;

        // Update state for PNL
        _refreshState(id);

        uint256 amount = strategyReserves[id].previewMint(shares);

        vm.prank(msg.sender);
        _increasePosition(id, amount, shares);
    }

    function decreasePositionWithdraw(
        uint16 id,
        uint16 amount
    ) external returns (uint256 shares) {
        id %= 4;

        // Update state for PNL
        _refreshState(id);

        IStrategyReserve reserve = strategyReserves[id];

        // Reduce for utilization.
        amount = uint16(Math.min(amount, usdc.balanceOf(address(reserve))));

        // Reduce for total value of shares.
        amount = uint16(
            Math.min(
                amount,
                reserve.previewRedeem(reserve.balanceOf(msg.sender))
            )
        );

        // Get shares that must be burned to recover the assets.
        shares = reserve.previewWithdraw(amount);

        vm.startPrank(msg.sender);
        _reduceLenderPosition(id, amount, shares);
        vm.stopPrank();

        return shares;
    }

    function decreasePositionRedeem(uint256 id, uint16 shares) external {
        id %= 4;

        // Update state for PNL
        _refreshState(id);

        IStrategyReserve reserve = strategyReserves[id];

        uint256 amount = reserve.previewRedeem(shares);

        // Reduce for utilization.
        amount = uint16(Math.min(amount, usdc.balanceOf(address(reserve))));

        // Reduce for total value of shares.
        amount = uint16(
            Math.min(
                amount,
                reserve.previewRedeem(reserve.balanceOf(msg.sender))
            )
        );

        // Get shares that must be burned to recover the assets.
        shares = uint16(reserve.previewWithdraw(amount));

        vm.startPrank(msg.sender);
        _redeemLenderPosition(id, amount, shares);
        vm.stopPrank();
    }

    // Strategy Account.

    function addCollateral(uint256 id, uint16 amount) external {
        IStrategyAccount strategyAccount = strategyAccounts[
            _getStrategyAccountId(id)
        ];
        IStrategyBank strategyBank = getStrategyBank(strategyAccount);

        IStrategyBank.StrategyAccountHoldings memory holdings = strategyBank
            .getStrategyAccountHoldings(address(strategyAccount));
        _simpleAddCollateral(id, holdings.loan);

        amount = uint16(
            Math.max(amount, TestConstants.MINIMUM_COLLATERAL_BALANCE)
        );

        _addCollateral(_getStrategyAccountId(id), amount);
    }

    function repayLoan(uint256 id, uint16 amount) external {
        uint256 strategyId = _getStrategyAccountId(id);
        IStrategyAccount strategyAccount = strategyAccounts[strategyId];
        IStrategyBank strategyBank = getStrategyBank(strategyAccount);

        IStrategyBank.StrategyAccountHoldings memory holdings = strategyBank
            .getStrategyAccountHoldings(address(strategyAccount));

        // refresh state.
        borrow(id, 0);

        uint256 healthScore = holdings.getHealthScore(
            usdc.balanceOf(address(strategyAccount))
        );
        if (healthScore < strategyBank.LIQUIDATABLE_HEALTH_SCORE()) {
            return;
        }

        uint256 updatedAmount = Math.max(
            amount,
            TestConstants.MINIMUM_COLLATERAL_BALANCE
        );

        // Can't repay more than loan.
        updatedAmount = Math.min(holdings.loan, updatedAmount);

        // Cannot repay without a loan.
        if (updatedAmount == 0) {
            return;
        }

        // Must borrow as sender.
        vm.startPrank(strategyAccount.getOwner());
        strategyAccount.executeRepayLoan(updatedAmount);
        vm.stopPrank();
    }

    function withdrawCollateral(
        uint256 id,
        uint16 amount,
        bool isSoftWithdraw
    ) external {
        uint256 strategyId = _getStrategyAccountId(id);
        IStrategyAccount strategyAccount = strategyAccounts[strategyId];
        StrategyBank strategyBank = StrategyBank(
            address(getStrategyBank(strategyAccount))
        );

        IStrategyBank.StrategyAccountHoldings memory holdings = strategyBank
            .getStrategyAccountHoldingsAfterPayingInterest(
                address(strategyAccount)
            );
        _simpleAddCollateral(id, holdings.loan);

        uint256 updatedAmount = Math.max(
            amount,
            TestConstants.MINIMUM_COLLATERAL_BALANCE
        );

        if (holdings.collateral == 0) {
            _simpleAddCollateral(id, updatedAmount);
            holdings.collateral += updatedAmount;
        }

        uint256 finalAmount = updatedAmount % holdings.collateral;

        if (isSoftWithdraw) {
            uint256 withdrawableCollateral = strategyBank
                .getWithdrawableCollateral(address(strategyAccount));
            finalAmount = Math.min(finalAmount, withdrawableCollateral);
        }

        if (
            finalAmount != holdings.collateral &&
            holdings.collateral - finalAmount <
            TestConstants.MINIMUM_COLLATERAL_BALANCE
        ) {
            return;
        }

        if (!isSoftWithdraw) {
            holdings.collateral -= finalAmount;
        }

        uint256 healthScore = holdings.getHealthScore(
            usdc.balanceOf(address(strategyAccount))
        );
        if (healthScore < strategyBank.minimumOpenHealthScore_()) {
            return;
        }

        vm.startPrank(msg.sender);
        _withdrawCollateral(strategyId, finalAmount, isSoftWithdraw);
        vm.stopPrank();
    }

    // Utilities.

    function addAccount(uint16 id, address owner) external {
        id %= uint16(strategyBanks.length);

        IStrategyAccount sa = IStrategyAccount(
            strategyBanks[id].executeOpenAccount(owner)
        );

        _strategyAccountIndexMapping[owner].push(strategyAccounts.length);

        strategyAccounts.push(StrategyAccountMock(address(sa)));
    }

    function simulateProfitOrLoss(
        uint256 id,
        uint16 amount,
        bool isProfit
    ) external {
        // There are always a constant number of accounts gt 0.
        id %= strategyAccounts.length;
        IStrategyAccount strategyAccount = strategyAccounts[id];
        IStrategyBank strategyBank = getStrategyBank(strategyAccount);

        IStrategyBank.StrategyAccountHoldings memory holdings = strategyBank
            .getStrategyAccountHoldings(address(strategyAccount));

        // Cannot have profit or loss if there is no loan.
        if (holdings.loan == 0) {
            return;
        }

        uint256 saBalance = usdc.balanceOf(address(strategyAccount));
        uint256 finalAmount = amount;
        if (!isProfit && saBalance > 0) {
            finalAmount %= saBalance;
        }

        _simulateProfitOrLoss(strategyAccount, finalAmount, isProfit);
    }

    // Getters

    function getAllStrategyAccounts()
        external
        view
        returns (StrategyAccountMock[] memory)
    {
        return strategyAccounts;
    }

    function getLenderExposureIndices(
        uint256 tokenId
    ) external view returns (uint256[] memory exposures) {
        return EnumerableSet.values(_lenderExposures[tokenId]);
    }

    function getTokens(
        address lender
    ) external view returns (uint256[] memory tokens) {
        return _tokenMapping[lender];
    }

    // ============ Public Functions ============

    function borrow(uint256 id, uint16 amount) public {
        uint256 strategyId = _getStrategyAccountId(id);
        IStrategyAccount strategyAccount = strategyAccounts[strategyId];
        IStrategyBank strategyBank = getStrategyBank(strategyAccount);

        IStrategyBank.StrategyAccountHoldings memory holdings = strategyBank
            .getStrategyAccountHoldings(address(strategyAccount));

        uint256 updatedAmount = Math.max(
            amount,
            TestConstants.MINIMUM_COLLATERAL_BALANCE
        );

        // Add collateral to be safe - make sure there is collateral for the new loan
        // and old loan in case it was potentially all.
        _simpleAddCollateral(id, updatedAmount + holdings.loan);

        IStrategyReserve reserve = strategyBank.STRATEGY_RESERVE();

        uint256 maxUtilizable = usdc.balanceOf(address(reserve));

        // Can only borrow the minimum of utilizable funds and leverage.
        uint256 viableLoan = Math.min(updatedAmount, maxUtilizable);

        // Must borrow as sender.
        vm.startPrank(msg.sender);
        _borrow(strategyId, viableLoan);
        vm.stopPrank();
    }

    function getStrategyBank(
        IStrategyAccount strategyAccount
    ) public view returns (IStrategyBank strategyBank) {
        // If called by invariants arbitrarily without a real strategy account
        // handle and return nonesense value.
        bool seen = false;
        for (uint256 i = 0; i < strategyAccounts.length; i++) {
            if (strategyAccounts[i] == strategyAccount) {
                seen = true;
            }
        }
        if (!seen) {
            return IStrategyBank(address(0));
        }

        return strategyAccount.STRATEGY_BANK();
    }

    // ============ Internal Functions ============

    // Add collateral as setup for other calls without validating.
    function _simpleAddCollateral(uint256 id, uint256 amount) internal {
        id = _getStrategyAccountId(id);
        IStrategyAccount strategyAccount = strategyAccounts[id];
        IStrategyBank strategyBank = strategyAccount.STRATEGY_BANK();

        TestUtilities.mintAndApprove(usdc, amount, address(strategyBank));
        strategyAccount.executeAddCollateral(amount);
    }

    // Strategy Account.

    function _getStrategyAccountId(
        uint256 id
    ) internal view returns (uint256 strategyAccountId) {
        uint256 index = id % _strategyAccountIndexMapping[msg.sender].length;
        return _strategyAccountIndexMapping[msg.sender][index];
    }
}

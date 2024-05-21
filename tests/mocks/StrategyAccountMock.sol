// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { StrategyAccount } from "../../contracts/core/StrategyAccount.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IStrategyAccount
} from "../../contracts/interfaces/IStrategyAccount.sol";
import { TestConstants } from "../testLibraries/TestConstants.sol";
import {
    IStrategyController
} from "../../contracts/interfaces/IStrategyController.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract StrategyAccountMock is StrategyAccount {
    using SafeERC20 for IERC20;

    uint256 totalAccountValue;
    uint256 tempRepay;
    IERC20 strategyAsset;

    bool failLiquidation;

    // ============ Initializer ============

    function initialize(
        address owner,
        IStrategyController strategyController
    ) external initializer {
        __StrategyAccount_init(owner, strategyController);

        strategyAsset = strategyController.STRATEGY_ASSET();
    }

    // ============ External Functions ============

    function deployFunds(uint256 amount) external {
        strategyAsset.transfer(msg.sender, amount);
    }

    function experienceProfit(uint256 amount) external {
        totalAccountValue += amount;
    }

    function experienceLoss(uint256 amount) external {
        totalAccountValue -= amount;

        strategyAsset.safeTransfer(TestConstants.DUMP_ADDRESS, amount);
    }

    function setFailLiquidation(bool fail) external {
        failLiquidation = fail;
    }

    function getAccountValue() public view override returns (uint256) {
        return totalAccountValue;
    }

    function _afterProcessLiquidation(uint256 loanLoss) internal override {
        totalAccountValue = 0;
    }

    function _isLiquidationFinished()
        internal
        view
        override
        returns (bool finished)
    {
        return !failLiquidation;
    }

    function _afterBorrow(uint256 requestedAmount) internal override {
        totalAccountValue += requestedAmount;
    }

    function _beforeRepay(uint256 repayAmount) internal override {
        tempRepay = repayAmount;
    }

    function _afterRepay() internal override {
        // If loss then cannot reduce by full amount.
        totalAccountValue -= Math.min(totalAccountValue, tempRepay);
        tempRepay = 0;
    }

    function _getAvailableStrategyAsset()
        internal
        view
        override
        returns (uint256)
    {
        return totalAccountValue;
    }
}

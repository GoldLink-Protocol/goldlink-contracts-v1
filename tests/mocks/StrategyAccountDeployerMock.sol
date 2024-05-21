// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { StrategyAccountMock } from "./StrategyAccountMock.sol";
import {
    IStrategyAccountDeployer
} from "../../contracts/interfaces/IStrategyAccountDeployer.sol";
import { StrategyBank } from "../../contracts/core/StrategyBank.sol";
import {
    IStrategyController
} from "../../contracts/interfaces/IStrategyController.sol";

contract StrategyAccountDeployerMock is IStrategyAccountDeployer {
    function deployAccount(
        address owner,
        IStrategyController strategyController
    ) external override returns (address) {
        StrategyAccountMock strategyAccount = new StrategyAccountMock();
        strategyAccount.initialize(owner, strategyController);
        return address(strategyAccount);
    }
}

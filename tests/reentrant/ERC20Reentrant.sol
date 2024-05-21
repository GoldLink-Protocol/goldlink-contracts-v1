// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { GoldLinkERC20Mock } from "../mocks/GoldLinkERC20Mock.sol";
import { TestUtilities } from "../testLibraries/TestUtilities.sol";
import { ProtocolDeployer } from "../ProtocolDeployer.sol";
import { StrategyAccount } from "../../contracts/core/StrategyAccount.sol";
import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import { StrategyReserve } from "../../contracts/core/StrategyReserve.sol";

import "forge-std/Test.sol";

contract ERC20Reentrant is Test, GoldLinkERC20Mock {
    ProtocolDeployer private _deployer;

    bool normal = false;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) GoldLinkERC20Mock(name_, symbol_, decimals_) {}

    function flipNormal() external {
        normal = !normal;
    }

    function setDeployer(ProtocolDeployer deployer) external {
        _deployer = deployer;
    }

    function transfer(
        address to,
        uint256 value
    ) public override returns (bool) {
        _maliciousCalls();

        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool) {
        _maliciousCalls();

        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function _maliciousCalls() internal {
        if (normal) {
            return;
        }

        IStrategyBank sb = _deployer.strategyBanks(0);
        StrategyReserve sr = StrategyReserve(address(sb.STRATEGY_RESERVE()));

        sr.deposit(1, msg.sender);
    }
}

// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import { TestConstants } from "./testLibraries/TestConstants.sol";
import { IStrategyBank } from "../contracts/interfaces/IStrategyBank.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TestUtilities } from "./testLibraries/TestUtilities.sol";
import { StrategyAccountMock } from "./mocks/StrategyAccountMock.sol";
import { IStrategyAccount } from "../contracts/interfaces/IStrategyAccount.sol";
import { IStrategyReserve } from "../contracts/interfaces/IStrategyReserve.sol";
import { StrategyController } from "../contracts/core/StrategyController.sol";
import { StrategyReserve } from "../contracts/core/StrategyReserve.sol";
import {
    StrategyAccountDeployerMock
} from "./mocks/StrategyAccountDeployerMock.sol";
import {
    IStrategyAccountDeployer
} from "../contracts/interfaces/IStrategyAccountDeployer.sol";
import { ERC20Reentrant } from "./reentrant/ERC20Reentrant.sol";
import { GoldLinkERC20Mock } from "./mocks/GoldLinkERC20Mock.sol";
import {
    IStrategyController
} from "../contracts/interfaces/IStrategyController.sol";

contract ProtocolDeployer {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    uint256 public immutable STRATEGY_COUNT = 4;

    GoldLinkERC20Mock public immutable usdc;
    GoldLinkERC20Mock immutable usdt;
    GoldLinkERC20Mock immutable arb;
    GoldLinkERC20Mock immutable link;
    GoldLinkERC20Mock immutable weth;
    GoldLinkERC20Mock immutable wbtc;
    ERC20Reentrant immutable fakeusdc;

    // ============ Storage Variables ============

    IStrategyController[] public strategyControllers;
    IStrategyReserve[] public strategyReserves;
    IStrategyBank[] public strategyBanks;

    StrategyAccountMock[] public strategyAccounts;

    // ============ Constructor ============

    constructor(bool reentrant) {
        usdc = new GoldLinkERC20Mock("USD Circle", "USDC", 6);
        usdt = new GoldLinkERC20Mock("USD Tether", "USDT", 6);
        link = new GoldLinkERC20Mock("Chainlink ", "LINK", 18);
        weth = new GoldLinkERC20Mock("Wrapped Ether", "WETH", 18);
        wbtc = new GoldLinkERC20Mock("Wrapped Bitcoin", "WBTC", 8);
        fakeusdc = new ERC20Reentrant(
            "Reentrant malicious contract",
            "EVIL",
            6
        ); // TODO: Rename from fakeusdc to something more clear.
        arb = new GoldLinkERC20Mock("Arbitrum", "ARB", 18);
        fakeusdc.setDeployer(ProtocolDeployer(this));

        for (uint256 i = 0; i < 4; i++) {
            (
                IStrategyReserve strategyReserve,
                IStrategyBank strategyBank,
                IStrategyController strategyController,
                IStrategyAccount strategyAccount
            ) = _createDefaultStrategy(reentrant ? fakeusdc : usdc);

            strategyReserves.push(strategyReserve);
            strategyBanks.push(strategyBank);
            strategyControllers.push(strategyController);
            strategyAccounts.push(
                StrategyAccountMock(address(strategyAccount))
            );
        }
    }

    function _createDefaultStrategy(
        IERC20 strategyAsset
    )
        internal
        returns (
            IStrategyReserve strategyReserve,
            IStrategyBank strategyBank,
            IStrategyController strategyController,
            IStrategyAccount strategyAccount
        )
    {
        StrategyAccountDeployerMock strategyAccountDeployerMock = new StrategyAccountDeployerMock();
        (strategyReserve, strategyBank, strategyController) = _createStrategy(
            strategyAsset,
            TestUtilities.defaultBankParameters(
                IStrategyAccountDeployer(address(strategyAccountDeployerMock))
            ),
            TestConstants.defaultReserveParameters()
        );

        strategyAccount = IStrategyAccount(
            strategyBank.executeOpenAccount(address(this))
        );
    }

    function _createStrategy(
        IERC20 strategyAsset,
        IStrategyBank.BankParameters memory bankParameters,
        IStrategyReserve.ReserveParameters memory reserveParameters
    )
        internal
        returns (
            IStrategyReserve strategyReserve,
            IStrategyBank strategyBank,
            IStrategyController strategyController
        )
    {
        // The strategy owner will be this test contract.
        address strategyOwner = address(this);

        // Create the strategy controller.
        // The controller will create the reserve and bank.
        strategyController = new StrategyController(
            strategyOwner,
            strategyAsset,
            reserveParameters,
            bankParameters
        );
        strategyReserve = strategyController.STRATEGY_RESERVE();
        strategyBank = strategyController.STRATEGY_BANK();

        // Return the newly deployed reserve, bank and controller.
        return (strategyReserve, strategyBank, strategyController);
    }
}

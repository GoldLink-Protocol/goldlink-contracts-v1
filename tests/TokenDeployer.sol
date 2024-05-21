// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { GoldLinkERC20Mock } from "./mocks/GoldLinkERC20Mock.sol";
import { ERC20Reentrant } from "./reentrant/ERC20Reentrant.sol";

contract TokenDeployer {
    // ============ Storage Variables ============

    GoldLinkERC20Mock public immutable usdc;
    GoldLinkERC20Mock immutable usdt;
    GoldLinkERC20Mock immutable arb;
    GoldLinkERC20Mock immutable link;
    GoldLinkERC20Mock immutable weth;
    GoldLinkERC20Mock immutable wbtc;
    ERC20Reentrant immutable fakeusdc;

    constructor() {
        usdc = new GoldLinkERC20Mock("USD Circle", "USDC", 6);
        usdt = new GoldLinkERC20Mock("USD Tether", "USDT", 6);
        link = new GoldLinkERC20Mock("Chainlink ", "LINK", 18);
        weth = new GoldLinkERC20Mock("Wrapped Ether", "WETH", 18);
        wbtc = new GoldLinkERC20Mock("Wrapped Bitcoin", "WBTC", 8);
        fakeusdc = new ERC20Reentrant(
            "Reentrant malicious contract",
            "EVIL",
            6
        );
        arb = new GoldLinkERC20Mock("Arbitrum", "ARB", 18);
    }
}

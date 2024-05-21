// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { GoldLinkERC20Mock } from "./GoldLinkERC20Mock.sol";

contract GoldLinkERC20MockTest is Test {
    // ============ Storage Variables ============

    GoldLinkERC20Mock goldLinkERC20Mock;

    // ============ Setup ============

    function setUp() public {
        goldLinkERC20Mock = new GoldLinkERC20Mock("USD Circle", "USDC", 6);
    }

    function testDecimals() public {
        assertEq(goldLinkERC20Mock.decimals(), 6);
    }

    function testMintAndBurn() public {
        assertTrue(goldLinkERC20Mock.mint(address(this), 100));
        assertEq(goldLinkERC20Mock.balanceOf(address(this)), 100);

        assertTrue(goldLinkERC20Mock.burnFrom(address(this), 100));
        assertEq(goldLinkERC20Mock.balanceOf(address(this)), 0);
    }

    function testSetZeroMinter() public {
        vm.expectRevert();
        goldLinkERC20Mock.setMinter(address(0));
    }
}

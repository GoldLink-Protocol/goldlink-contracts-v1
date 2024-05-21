// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";

import { GoldLinkERC20Mock } from "../../../tests/mocks/GoldLinkERC20Mock.sol";
import {
    StrategyController
} from "../../../contracts/core/StrategyController.sol";
import { StrategyBank } from "../../../contracts/core/StrategyBank.sol";
import { StrategyReserve } from "../../../contracts/core/StrategyReserve.sol";
import {
    IInterestRateModel
} from "../../../contracts/interfaces/IInterestRateModel.sol";
import { StrategyAccount } from "../../../contracts/core/StrategyAccount.sol";

// Run: forge script scripts/testnet/MintToScript.sol --rpc-url ${RPC URL} --broadcast

// Controller: https://sepolia.arbiscan.io/address/0x40A633EeF249F21D95C8803b7144f19AAfeEF7ae
// Mock ERC20: https://sepolia.arbiscan.io/address/0x773330693cb7d5D233348E25809770A32483A940
// Bank: https://sepolia.arbiscan.io/address/0xD4324a5f29147688fB4ca959e901b0Ff50Bd8e3a
// Reserve: https://sepolia.arbiscan.io/address/0x3e3c1e5477f5F3261D7c25088566e548405B724B

contract MintToScript is Script {
    string constant TEST_OWNER_PRIVATE_KEY = "TEST_OWNER_PRIVATE_KEY";

    string constant TEST_ACCOUNT_3_PUBLIC_KEY = "TEST_ACCOUNT_3_PUBLIC_KEY";

    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint(TEST_OWNER_PRIVATE_KEY);

        address mintTo = vm.envAddress(TEST_ACCOUNT_3_PUBLIC_KEY);

        // contract for protocol asset.
        GoldLinkERC20Mock erc20 = GoldLinkERC20Mock(
            address(0x773330693cb7d5D233348E25809770A32483A940)
        );

        vm.startBroadcast(privateKey);

        erc20.mint(mintTo, 1e30);
        console.log(erc20.balanceOf(mintTo));
        vm.stopBroadcast();
    }
}

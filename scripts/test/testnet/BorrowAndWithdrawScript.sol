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
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Run: forge script scripts/testnet/BorrowAndWithdrawScript.sol --rpc-url ${RPC URL} --broadcast

// Controller: https://sepolia.arbiscan.io/address/0x40A633EeF249F21D95C8803b7144f19AAfeEF7ae
// Mock ERC20: https://sepolia.arbiscan.io/address/0x773330693cb7d5D233348E25809770A32483A940
// Bank: https://sepolia.arbiscan.io/address/0xD4324a5f29147688fB4ca959e901b0Ff50Bd8e3a
// Reserve: https://sepolia.arbiscan.io/address/0x3e3c1e5477f5F3261D7c25088566e548405B724B

contract BorrowAndWithdrawScript is Script {
    string constant TEST_OWNER_PRIVATE_KEY = "TEST_OWNER_PRIVATE_KEY";

    string constant TEST_ACCOUNT_2_PUBLIC_KEY = "TEST_ACCOUNT_2_PUBLIC_KEY";
    string constant TEST_ACCOUNT_2_PRIVATE_KEY = "TEST_ACCOUNT_2_PRIVATE_KEY";
    string constant STRATEGY_ACCOUNT_FOR_ACCOUNT_2 =
        "STRATEGY_ACCOUNT_FOR_ACCOUNT_2";

    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint(TEST_OWNER_PRIVATE_KEY);

        address payable account2 = payable(
            vm.envAddress(TEST_ACCOUNT_2_PUBLIC_KEY)
        );
        uint256 privateKey2 = vm.envUint(TEST_ACCOUNT_2_PRIVATE_KEY);
        address strategyAccountAddress = vm.envAddress(
            STRATEGY_ACCOUNT_FOR_ACCOUNT_2
        );

        // contracts to include.
        GoldLinkERC20Mock erc20 = GoldLinkERC20Mock(
            address(0x773330693cb7d5D233348E25809770A32483A940)
        );
        StrategyBank bank = StrategyBank(
            address(0xD4324a5f29147688fB4ca959e901b0Ff50Bd8e3a)
        );

        // Start filling account.
        vm.startBroadcast(privateKey);
        erc20.mint(strategyAccountAddress, 1e8);
        vm.stopBroadcast();

        // Start user 3.
        vm.startBroadcast(privateKey2);

        // Create a strategy account and perform borrow actions.
        erc20.approve(address(bank), 1e20);
        {
            StrategyAccount account = StrategyAccount(strategyAccountAddress);

            IERC20[] memory withdrawAssets = new IERC20[](1);
            withdrawAssets[0] = erc20;

            uint256[] memory withdrawAmounts = new uint256[](1);
            withdrawAmounts[0] = 1e8;

            account.executeWithdrawErc20Assets(
                account2,
                withdrawAssets,
                withdrawAmounts
            );
        }

        vm.stopBroadcast();
    }
}

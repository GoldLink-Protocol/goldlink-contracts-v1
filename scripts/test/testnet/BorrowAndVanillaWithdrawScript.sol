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

// Run: forge script scripts/testnet/BorrowAndVanillaWithdrawScript.sol --rpc-url ${RPC URL} --broadcast

// Controller: https://sepolia.arbiscan.io/address/0x40A633EeF249F21D95C8803b7144f19AAfeEF7ae
// Mock ERC20: https://sepolia.arbiscan.io/address/0x773330693cb7d5D233348E25809770A32483A940
// Bank: https://sepolia.arbiscan.io/address/0xD4324a5f29147688fB4ca959e901b0Ff50Bd8e3a
// Reserve: https://sepolia.arbiscan.io/address/0x3e3c1e5477f5F3261D7c25088566e548405B724B

contract BorrowAndVanillaWithdrawScript is Script {
    string constant TEST_ACCOUNT_1_PUBLIC_KEY = "TEST_ACCOUNT_1_PUBLIC_KEY";
    string constant TEST_ACCOUNT_1_PRIVATE_KEY = "TEST_ACCOUNT_1_PRIVATE_KEY";
    string constant STRATEGY_ACCOUNT_FOR_ACCOUNT_1 =
        "STRATEGY_ACCOUNT_FOR_ACCOUNT_1";

    string constant TEST_ACCOUNT_2_PUBLIC_KEY = "TEST_ACCOUNT_2_PUBLIC_KEY";

    function setUp() public {}

    function run() public {
        uint256 privateKey1 = vm.envUint(TEST_ACCOUNT_1_PRIVATE_KEY);
        address strategyAccountAddress = vm.envAddress(
            STRATEGY_ACCOUNT_FOR_ACCOUNT_1
        );

        address account2 = vm.envAddress(TEST_ACCOUNT_2_PUBLIC_KEY);

        // contracts to include.
        GoldLinkERC20Mock erc20 = GoldLinkERC20Mock(
            address(0x773330693cb7d5D233348E25809770A32483A940)
        );
        StrategyReserve reserve = StrategyReserve(
            address(0x3e3c1e5477f5F3261D7c25088566e548405B724B)
        );

        // Start user 2.
        vm.startBroadcast(privateKey1);

        // Start lending and do some minimal withdrawing.
        erc20.approve(address(reserve), 1e20);

        reserve.deposit(1e10, account2);

        // Create a strategy account and perform borrow actions.
        {
            StrategyAccount account = StrategyAccount(strategyAccountAddress);

            account.executeAddCollateral(1.3256e10);
            account.executeBorrow(2.5e10);
            account.executeRepayLoan(2.5e10);
            account.executeWithdrawCollateral(account2, 1.3e10, true);
        }

        vm.stopBroadcast();
    }
}

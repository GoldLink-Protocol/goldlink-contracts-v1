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
import {
    StrategyAccountMock
} from "../../../tests/mocks/StrategyAccountMock.sol";

// Run: forge script scripts/testnet/LiquidationScript.sol --rpc-url ${RPC URL} --broadcast

// Controller: https://sepolia.arbiscan.io/address/0x40A633EeF249F21D95C8803b7144f19AAfeEF7ae
// Mock ERC20: https://sepolia.arbiscan.io/address/0x773330693cb7d5D233348E25809770A32483A940
// Bank: https://sepolia.arbiscan.io/address/0xD4324a5f29147688fB4ca959e901b0Ff50Bd8e3a
// Reserve: https://sepolia.arbiscan.io/address/0x3e3c1e5477f5F3261D7c25088566e548405B724B

contract LiquidationScript is Script {
    string constant TEST_ACCOUNT_3_PUBLIC_KEY = "TEST_ACCOUNT_3_PUBLIC_KEY";
    string constant TEST_ACCOUNT_3_PRIVATE_KEY = "TEST_ACCOUNT_3_PRIVATE_KEY";

    function setUp() public {}

    function run() public {
        address account3 = vm.envAddress(TEST_ACCOUNT_3_PUBLIC_KEY);
        uint256 privateKey3 = vm.envUint(TEST_ACCOUNT_3_PRIVATE_KEY);

        // contracts to include.
        GoldLinkERC20Mock erc20 = GoldLinkERC20Mock(
            address(0x773330693cb7d5D233348E25809770A32483A940)
        );
        StrategyBank bank = StrategyBank(
            address(0xD4324a5f29147688fB4ca959e901b0Ff50Bd8e3a)
        );

        // Start user 3.
        vm.startBroadcast(privateKey3);

        // Create a strategy account and perform borrow actions.
        erc20.approve(address(bank), 1e20);
        {
            StrategyAccountMock account = StrategyAccountMock(
                bank.executeOpenAccount(account3)
            );

            account.executeAddCollateral(1.0008e10);
            account.executeBorrow(1.5611112e10);

            StrategyBank.StrategyAccountHoldings memory holdings = bank
                .getStrategyAccountHoldingsAfterPayingInterest(
                    address(account)
                );
            account.experienceLoss(holdings.loan);

            account.executeInitiateLiquidation();
            account.executeProcessLiquidation();
        }

        vm.stopBroadcast();
    }
}

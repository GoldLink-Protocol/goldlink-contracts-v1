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

// Run: forge script scripts/testnet/OwnerActionsAndLendScript.sol --rpc-url ${RPC URL} --broadcast

// Controller: https://sepolia.arbiscan.io/address/0x40A633EeF249F21D95C8803b7144f19AAfeEF7ae
// Mock ERC20: https://sepolia.arbiscan.io/address/0x773330693cb7d5D233348E25809770A32483A940
// Bank: https://sepolia.arbiscan.io/address/0xD4324a5f29147688fB4ca959e901b0Ff50Bd8e3a
// Reserve: https://sepolia.arbiscan.io/address/0x3e3c1e5477f5F3261D7c25088566e548405B724B

contract OwnerActionsAndLendScript is Script {
    string constant TEST_OWNER_PUBLIC_KEY = "TEST_OWNER_PUBLIC_KEY";
    string constant TEST_OWNER_PRIVATE_KEY = "TEST_OWNER_PRIVATE_KEY";

    string constant TEST_ACCOUNT_1_PUBLIC_KEY = "TEST_ACCOUNT_1_PUBLIC_KEY";

    string constant TEST_ACCOUNT_2_PUBLIC_KEY = "TEST_ACCOUNT_2_PUBLIC_KEY";

    function setUp() public {}

    function run() public {
        address newOwner = vm.envAddress(TEST_OWNER_PUBLIC_KEY);
        uint256 privateKey = vm.envUint(TEST_OWNER_PRIVATE_KEY);

        address account1 = vm.envAddress(TEST_ACCOUNT_1_PUBLIC_KEY);

        address account2 = vm.envAddress(TEST_ACCOUNT_2_PUBLIC_KEY);

        // contracts to include.
        GoldLinkERC20Mock erc20 = GoldLinkERC20Mock(
            address(0x773330693cb7d5D233348E25809770A32483A940)
        );
        StrategyBank bank = StrategyBank(
            address(0xD4324a5f29147688fB4ca959e901b0Ff50Bd8e3a)
        );
        StrategyReserve reserve = StrategyReserve(
            address(0x3e3c1e5477f5F3261D7c25088566e548405B724B)
        );

        // // Start user 1.
        vm.startBroadcast(privateKey);

        // set erc20 balances.
        if (erc20.balanceOf(newOwner) < 1e10) {
            erc20.mint(newOwner, 1e15);
            erc20.mint(account1, 1e15);
            erc20.mint(account2, 1e15);
        }

        console.log(
            erc20.balanceOf(newOwner),
            erc20.balanceOf(account1),
            erc20.balanceOf(account2)
        );

        // Tweak input parameters.
        {
            /// Update reserve TVL.
            reserve.updateReserveTVLCap(reserve.tvlCap_() + 10);

            /// Update reserve TVL.
            (
                uint256 optimalUtilization,
                uint256 baseInterestRate,
                uint256 rateSlope1,
                uint256 rateSlope2
            ) = reserve.model_();
            optimalUtilization += 10;
            reserve.updateModel(
                IInterestRateModel.InterestRateModelParameters(
                    optimalUtilization,
                    baseInterestRate,
                    rateSlope1,
                    rateSlope2
                )
            );

            /// Update minimum open health score.
            bank.updateMinimumOpenHealthScore(
                bank.minimumOpenHealthScore_() + 10
            );
        }

        // Start lending and do some minimal withdrawing.
        erc20.approve(address(reserve), 1e20);

        reserve.deposit(1.7e10, account1);
        reserve.mint(2.2e10, newOwner);
        reserve.withdraw(1.4e10, account2, newOwner);
        reserve.redeem(1.3e10, account1, newOwner);

        vm.stopBroadcast();
    }
}

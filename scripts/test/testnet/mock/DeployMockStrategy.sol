// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";

import {
    StrategyAccountDeployerMock
} from "../../../../tests/mocks/StrategyAccountDeployerMock.sol";
import {
    GoldLinkERC20Mock
} from "../../../../tests/mocks/GoldLinkERC20Mock.sol";

/*
    Deployment Steps:
    1) Get environment variables to populate parameters.
    2) Deploy Mock ERC20.
    3) Optionally send mocked ERC20 funds to
    owner if an initial send amount is specified.
    4) Deploy mock strategy deployer.
*/
contract DeployMockStrategy is Script {
    /// The private key for the deployer account.
    string constant DEPLOYER_PRIVATE_KEY_ENV_KEY = "DEPLOYER_PRIVATE_KEY";

    /// @notice The mock ERC20 token decimals.
    string constant MOCK_TOKEN_DECIMALS_ENV_KEY = "MOCK_TOKEN_DECIMALS";
    /// @notice Optional mock ERC20 send amount to deployer.
    string constant MOCK_TOKEN_INITIAL_FUND_AMOUNT_ENV_KEY =
        "MOCK_TOKEN_INITIAL_FUND_AMOUNT";

    function setup() public {}

    function run() public {
        uint8 mockDecimals = uint8(vm.envUint(MOCK_TOKEN_DECIMALS_ENV_KEY));

        uint256 pkey = vm.envUint(DEPLOYER_PRIVATE_KEY_ENV_KEY);
        address ethAddress = vm.addr(pkey);

        vm.broadcast(pkey);

        GoldLinkERC20Mock erc20Mock = new GoldLinkERC20Mock(
            "Mock ERC20",
            "MOCK",
            mockDecimals
        );

        uint256 ownerSendAmount = vm.envUint(
            MOCK_TOKEN_INITIAL_FUND_AMOUNT_ENV_KEY
        );

        if (ownerSendAmount != 0) {
            vm.broadcast(pkey);
            erc20Mock.mint(ethAddress, ownerSendAmount);
        }

        vm.broadcast(pkey);
        StrategyAccountDeployerMock deployerMock = new StrategyAccountDeployerMock();

        console.log("ERC20 Mock:", address(erc20Mock));
        console.log("Deployer Mock:", address(deployerMock));
    }
}

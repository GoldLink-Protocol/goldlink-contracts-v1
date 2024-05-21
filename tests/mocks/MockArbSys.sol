// SPDX-License-Identifier: BUSL-1.1
//
// Adapted from https://github.com/gmx-io/gmx-synthetics/blob/178290846694d65296a14b9f4b6ff9beae28a7f7/contracts/mock/MockArbSys.sol

pragma solidity 0.8.20;

contract MockArbSys {
    function arbBlockNumber() external view returns (uint256) {
        return block.number;
    }

    function arbBlockHash(uint256 blockNumber) external view returns (bytes32) {
        return blockhash(blockNumber);
    }
}

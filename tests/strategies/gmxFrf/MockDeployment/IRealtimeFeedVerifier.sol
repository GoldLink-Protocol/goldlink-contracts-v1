// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// Borrowed from https://github.com/gmx-io/gmx-synthetics/blob/updates/contracts/oracle/IRealtimeFeedVerifier.sol

interface IRealtimeFeedVerifier {
    function verify(bytes memory data) external returns (bytes memory);
}

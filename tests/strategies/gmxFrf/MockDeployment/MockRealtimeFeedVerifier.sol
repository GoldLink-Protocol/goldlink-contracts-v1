// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IRealtimeFeedVerifier.sol";

// Borrowed From https://github.com/gmx-io/gmx-synthetics/blob/updates/contracts/mock/MockRealtimeFeedVerifier.sol
contract MockRealtimeFeedVerifier is IRealtimeFeedVerifier {
    function verify(bytes memory data) external pure returns (bytes memory) {
        return data;
    }
}

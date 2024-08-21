// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {
    IChainlinkDataStreamVerifier
} from "./IChainlinkDataStreamVerifier.sol";

contract MockChainlinkDataStreamVerifier is IChainlinkDataStreamVerifier {
    /**
     * @notice Verifies that the data encoded has been signed
     * correctly by routing to the correct verifier, and bills the user if applicable.
     * @param payload The encoded data to be verified, including the signed
     * report.
     * @return verifierResponse The encoded report from the verifier.
     */
    function verify(
        bytes calldata payload,
        bytes calldata /* parameterPayload */
    ) external payable returns (bytes memory verifierResponse) {
        return payload;
    }
}

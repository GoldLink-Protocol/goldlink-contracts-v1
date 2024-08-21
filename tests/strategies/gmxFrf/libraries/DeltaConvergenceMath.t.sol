// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {
    DeltaConvergenceMath
} from "../../../../contracts/strategies/gmxFrf/libraries/DeltaConvergenceMath.sol";

import {
    IGmxV2PositionTypes
} from "../../../../contracts/strategies/gmxFrf/interfaces/gmx/IGmxV2PositionTypes.sol";

import {
    PositionStoreUtils
} from "../../../../contracts/lib/gmx/position/PositionStoreUtils.sol";

contract DeltaConvergenceMathTest is Test {
    // ============ Setup ============

    function setUp() public {
        // Empty.
    }

    // ============ Get Increase Size Delta Tests ============

    function testGetIncreaseSizeDeltaLessCollateralAfter() public {
        assertEq(DeltaConvergenceMath.getIncreaseSizeDelta(1e18, 1e17, 1e6), 0);
    }

    function testGetIncreaseSizeDeltaEqualCollateralAfter() public {
        assertEq(DeltaConvergenceMath.getIncreaseSizeDelta(1e18, 1e18, 1e6), 0);
    }

    function testGetIncreaseSizeDeltaGreaterCollateralAfter() public {
        assertEq(
            DeltaConvergenceMath.getIncreaseSizeDelta(1e17, 1e18, 1e6),
            9e23
        );
    }

    function iToHex(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }

    function toHex16(bytes16 data) internal pure returns (bytes32 result) {
        result =
            (bytes32(data) &
                0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000) |
            ((bytes32(data) &
                0x0000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000000000) >>
                64);
        result =
            (result &
                0xFFFFFFFF000000000000000000000000FFFFFFFF000000000000000000000000) |
            ((result &
                0x00000000FFFFFFFF000000000000000000000000FFFFFFFF0000000000000000) >>
                32);
        result =
            (result &
                0xFFFF000000000000FFFF000000000000FFFF000000000000FFFF000000000000) |
            ((result &
                0x0000FFFF000000000000FFFF000000000000FFFF000000000000FFFF00000000) >>
                16);
        result =
            (result &
                0xFF000000FF000000FF000000FF000000FF000000FF000000FF000000FF000000) |
            ((result &
                0x00FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF0000) >>
                8);
        result =
            ((result &
                0xF000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000) >>
                4) |
            ((result &
                0x0F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F00) >>
                8);
        result = bytes32(
            0x3030303030303030303030303030303030303030303030303030303030303030 +
                uint256(result) +
                (((uint256(result) +
                    0x0606060606060606060606060606060606060606060606060606060606060606) >>
                    4) &
                    0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F) *
                7
        );
    }

    function toHex(bytes32 data) public pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "0x",
                    toHex16(bytes16(data)),
                    toHex16(bytes16(data << 128))
                )
            );
    }

    function bytes32ToString(
        bytes32 _bytes32
    ) public pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    // ============ Get Delta Proportion Tests ============

    function testGetDeltaProportionShort() public {
        (uint256 proportion, bool isShort) = DeltaConvergenceMath
            .getDeltaProportion(1e18, 5e17);
        assertEq(proportion, 2e18);
        assertTrue(isShort);
    }

    function testGetDeltaProportionLong() public {
        (uint256 proportion, bool isShort) = DeltaConvergenceMath
            .getDeltaProportion(5e17, 7.5e17);
        assertEq(proportion, 1.5e18);
        assertFalse(isShort);
    }

    function testGetDeltaProportionEqual() public {
        (uint256 proportion, bool isShort) = DeltaConvergenceMath
            .getDeltaProportion(1e18, 1e18);
        assertEq(proportion, 1e18);
        assertFalse(isShort);
    }
}

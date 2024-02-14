// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {Test} from "forge-std/Test.sol";
import "../src/libraries/NormalizedAmount.sol";
import "forge-std/console.sol";

contract NormalizationTest is Test {
    using NormalizedAmountLib for uint256;
    using NormalizedAmountLib for NormalizedAmount;

    function testNormalizationRoundTrip() public {
        uint8 decimals = 18;
        uint256 amount = 50 * 10 ** decimals;
        NormalizedAmount memory normalized = amount.normalize(decimals);
        uint256 roundTrip = normalized.denormalize(decimals);

        uint256 expectedAmount = 50 * 10 ** decimals;
        assertEq(expectedAmount, roundTrip);
    }

    function testAddOperatorNonZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 2 * 10 ** decimals[i];
            NormalizedAmount memory normalizedAmount = amount.normalize(decimals[i]);
            NormalizedAmount memory normalizedAmountOther = amountOther.normalize(decimals[i]);
            NormalizedAmount memory normalizedSum = normalizedAmount.add(normalizedAmountOther);

            NormalizedAmount memory expectedNormalizedSum =
                NormalizedAmount(uint64(7 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]);
            assert(expectedNormalizedSum.eq(normalizedSum));
        }
    }

    function testAddOperatorZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 0;
            NormalizedAmount memory normalizedAmount = amount.normalize(decimals[i]);
            NormalizedAmount memory normalizedAmountOther = amountOther.normalize(decimals[i]);
            NormalizedAmount memory normalizedSum = normalizedAmount.add(normalizedAmountOther);

            NormalizedAmount memory expectedNormalizedSum =
                NormalizedAmount(uint64(5 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]);
            assert(expectedNormalizedSum.eq(normalizedSum));
        }
    }

    function testAddOperatorDecimalsNotEqualRevert() public {
        uint8 decimals = 18;
        uint8 decimalsOther = 3;

        uint256 amount = 5 * 10 ** decimals;
        uint256 amountOther = 2 * 10 ** decimalsOther;
        NormalizedAmount memory normalizedAmount = amount.normalize(decimals);
        NormalizedAmount memory normalizedAmountOther = amountOther.normalize(decimalsOther);

        vm.expectRevert();
        normalizedAmount.add(normalizedAmountOther);
    }

    function testAddOperatorDecimalsNotEqualNoRevert() public pure {
        uint8[2] memory decimals = [18, 10];
        uint8[2] memory expectedDecimals = [8, 8];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 2 * 10 ** 9;
            NormalizedAmount memory normalizedAmount = amount.normalize(decimals[i]);
            NormalizedAmount memory normalizedAmountOther = amountOther.normalize(9);
            NormalizedAmount memory normalizedSum = normalizedAmount.add(normalizedAmountOther);

            NormalizedAmount memory expectedNormalizedSum =
                NormalizedAmount(uint64(7 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]);
            assert(expectedNormalizedSum.eq(normalizedSum));
        }
    }

    function testSubOperatorNonZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 2 * 10 ** decimals[i];
            NormalizedAmount memory normalizedAmount = amount.normalize(decimals[i]);
            NormalizedAmount memory normalizedAmountOther = amountOther.normalize(decimals[i]);
            NormalizedAmount memory normalizedSub = normalizedAmount.sub(normalizedAmountOther);

            NormalizedAmount memory expectedNormalizedSub =
                NormalizedAmount(uint64(3 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]);
            assert(expectedNormalizedSub.eq(normalizedSub));
        }
    }

    function testSubOperatorZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 0;
            NormalizedAmount memory normalizedAmount = amount.normalize(decimals[i]);
            NormalizedAmount memory normalizedAmountOther = amountOther.normalize(decimals[i]);
            NormalizedAmount memory normalizedSub = normalizedAmount.sub(normalizedAmountOther);

            NormalizedAmount memory expectedNormalizedSub =
                NormalizedAmount(uint64(5 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]);
            assert(expectedNormalizedSub.eq(normalizedSub));
        }
    }

    function testSubOperatorOverflow() public {
        uint8[2] memory decimals = [18, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 6 * 10 ** decimals[i];
            NormalizedAmount memory normalizedAmount = amount.normalize(decimals[i]);
            NormalizedAmount memory normalizedAmountOther = amountOther.normalize(decimals[i]);

            vm.expectRevert();
            normalizedAmount.sub(normalizedAmountOther);
        }
    }

    function testDifferentDecimals() public {
        uint8 sourceDecimals = 18;
        uint8 targetDecimals = 6;
        uint256 amount = 5 * 10 ** sourceDecimals;

        NormalizedAmount memory normalizedAmount = amount.normalize(sourceDecimals);
        // normalized to 8
        uint256 amountRoundTrip = normalizedAmount.denormalize(targetDecimals);
        // denormalize to 6
        uint256 expectedRoundTrip = 5 * 10 ** targetDecimals;

        assertEq(expectedRoundTrip, amountRoundTrip);
    }
}

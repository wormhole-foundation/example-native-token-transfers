// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {Test} from "forge-std/Test.sol";
import "../src/libraries/TrimmedAmount.sol";
import "forge-std/console.sol";

contract TrimmingTest is Test {
    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    function testTrimmingRoundTrip() public {
        uint8 decimals = 18;
        uint256 amount = 50 * 10 ** decimals;
        TrimmedAmount memory trimmed = amount.trim(decimals);
        uint256 roundTrip = trimmed.untrim(decimals);

        uint256 expectedAmount = 50 * 10 ** decimals;
        assertEq(expectedAmount, roundTrip);
    }

    function testAddOperatorNonZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 2 * 10 ** decimals[i];
            TrimmedAmount memory trimmedAmount = amount.trim(decimals[i]);
            TrimmedAmount memory trimmedAmountOther = amountOther.trim(decimals[i]);
            TrimmedAmount memory trimmedSum = trimmedAmount.add(trimmedAmountOther);

            TrimmedAmount memory expectedTrimmedSum =
                TrimmedAmount(uint64(7 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]);
            assert(expectedTrimmedSum.eq(trimmedSum));
        }
    }

    function testAddOperatorZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 0;
            TrimmedAmount memory trimmedAmount = amount.trim(decimals[i]);
            TrimmedAmount memory trimmedAmountOther = amountOther.trim(decimals[i]);
            TrimmedAmount memory trimmedSum = trimmedAmount.add(trimmedAmountOther);

            TrimmedAmount memory expectedTrimmedSum =
                TrimmedAmount(uint64(5 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]);
            assert(expectedTrimmedSum.eq(trimmedSum));
        }
    }

    function testAddOperatorDecimalsNotEqualRevert() public {
        uint8 decimals = 18;
        uint8 decimalsOther = 3;

        uint256 amount = 5 * 10 ** decimals;
        uint256 amountOther = 2 * 10 ** decimalsOther;
        TrimmedAmount memory trimmedAmount = amount.trim(decimals);
        TrimmedAmount memory trimmedAmountOther = amountOther.trim(decimalsOther);

        vm.expectRevert();
        trimmedAmount.add(trimmedAmountOther);
    }

    function testAddOperatorDecimalsNotEqualNoRevert() public pure {
        uint8[2] memory decimals = [18, 10];
        uint8[2] memory expectedDecimals = [8, 8];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 2 * 10 ** 9;
            TrimmedAmount memory trimmedAmount = amount.trim(decimals[i]);
            TrimmedAmount memory trimmedAmountOther = amountOther.trim(9);
            TrimmedAmount memory trimmedSum = trimmedAmount.add(trimmedAmountOther);

            TrimmedAmount memory expectedTrimmedSum =
                TrimmedAmount(uint64(7 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]);
            assert(expectedTrimmedSum.eq(trimmedSum));
        }
    }

    function testSubOperatorNonZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 2 * 10 ** decimals[i];
            TrimmedAmount memory trimmedAmount = amount.trim(decimals[i]);
            TrimmedAmount memory trimmedAmountOther = amountOther.trim(decimals[i]);
            TrimmedAmount memory trimmedSub = trimmedAmount.sub(trimmedAmountOther);

            TrimmedAmount memory expectedTrimmedSub =
                TrimmedAmount(uint64(3 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]);
            assert(expectedTrimmedSub.eq(trimmedSub));
        }
    }

    function testSubOperatorZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 0;
            TrimmedAmount memory trimmedAmount = amount.trim(decimals[i]);
            TrimmedAmount memory trimmedAmountOther = amountOther.trim(decimals[i]);
            TrimmedAmount memory trimmedSub = trimmedAmount.sub(trimmedAmountOther);

            TrimmedAmount memory expectedTrimmedSub =
                TrimmedAmount(uint64(5 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]);
            assert(expectedTrimmedSub.eq(trimmedSub));
        }
    }

    function testSubOperatorOverflow() public {
        uint8[2] memory decimals = [18, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 6 * 10 ** decimals[i];
            TrimmedAmount memory trimmedAmount = amount.trim(decimals[i]);
            TrimmedAmount memory trimmedAmountOther = amountOther.trim(decimals[i]);

            vm.expectRevert();
            trimmedAmount.sub(trimmedAmountOther);
        }
    }

    function testDifferentDecimals() public {
        uint8 sourceDecimals = 18;
        uint8 targetDecimals = 6;
        uint256 amount = 5 * 10 ** sourceDecimals;

        TrimmedAmount memory trimmedAmount = amount.trim(sourceDecimals);
        // trimmed to 8
        uint256 amountRoundTrip = trimmedAmount.untrim(targetDecimals);
        // untrim to 6
        uint256 expectedRoundTrip = 5 * 10 ** targetDecimals;

        assertEq(expectedRoundTrip, amountRoundTrip);
    }
}

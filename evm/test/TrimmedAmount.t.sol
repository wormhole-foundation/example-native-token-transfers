// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {Test, stdError} from "forge-std/Test.sol";
import "../src/libraries/TrimmedAmount.sol";
import "forge-std/console.sol";

contract TrimmingTest is Test {
    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    function test_packUnpack(uint64 amount, uint8 decimals) public {
        TrimmedAmount trimmed = packTrimmedAmount(amount, decimals);
        assertEq(trimmed.getAmount(), amount);
        assertEq(trimmed.getDecimals(), decimals);
    }

    function testTrimmingRoundTrip() public {
        uint8 decimals = 18;
        uint256 amount = 50 * 10 ** decimals;
        TrimmedAmount trimmed = amount.trim(decimals, 8);
        uint256 roundTrip = trimmed.untrim(decimals);

        uint256 expectedAmount = 50 * 10 ** decimals;
        assertEq(expectedAmount, roundTrip);
    }

    function testTrimLessThan8() public {
        uint8 decimals = 7;
        uint8 targetDecimals = 3;
        uint256 amount = 9123412342342;
        TrimmedAmount trimmed = amount.trim(decimals, targetDecimals);

        uint64 expectedAmount = 912341234;
        uint8 expectedDecimals = targetDecimals;
        assertEq(trimmed.getAmount(), expectedAmount);
        assertEq(trimmed.getDecimals(), expectedDecimals);
    }

    function testAddOperatorNonZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 2 * 10 ** decimals[i];
            TrimmedAmount trimmedAmount = amount.trim(decimals[i], 8);
            TrimmedAmount trimmedAmountOther = amountOther.trim(decimals[i], 8);
            TrimmedAmount trimmedSum = trimmedAmount + trimmedAmountOther;

            TrimmedAmount expectedTrimmedSum = packTrimmedAmount(
                uint64(7 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]
            );
            assert(expectedTrimmedSum == trimmedSum);
        }
    }

    function testAddOperatorZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 0;
            TrimmedAmount trimmedAmount = amount.trim(decimals[i], 8);
            TrimmedAmount trimmedAmountOther = amountOther.trim(decimals[i], 8);
            TrimmedAmount trimmedSum = trimmedAmount + trimmedAmountOther;

            TrimmedAmount expectedTrimmedSum = packTrimmedAmount(
                uint64(5 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]
            );
            assert(expectedTrimmedSum == trimmedSum);
        }
    }

    function testAddOperatorDecimalsNotEqualRevert() public {
        uint8 decimals = 18;
        uint8 decimalsOther = 3;

        uint256 amount = 5 * 10 ** decimals;
        uint256 amountOther = 2 * 10 ** decimalsOther;
        TrimmedAmount trimmedAmount = amount.trim(decimals, 8);
        TrimmedAmount trimmedAmountOther = amountOther.trim(decimalsOther, 8);

        vm.expectRevert(abi.encodeWithSelector(NumberOfDecimalsNotEqual.selector, 8, decimalsOther));
        trimmedAmount + trimmedAmountOther;
    }

    function testAddOperatorDecimalsNotEqualNoRevert() public pure {
        uint8[2] memory decimals = [18, 10];
        uint8[2] memory expectedDecimals = [8, 8];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 2 * 10 ** 9;
            TrimmedAmount trimmedAmount = amount.trim(decimals[i], 8);
            TrimmedAmount trimmedAmountOther = amountOther.trim(9, 8);
            TrimmedAmount trimmedSum = trimmedAmount + trimmedAmountOther;

            TrimmedAmount expectedTrimmedSum = packTrimmedAmount(
                uint64(7 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]
            );
            assert(expectedTrimmedSum == trimmedSum);
        }
    }

    function testSubOperatorNonZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 2 * 10 ** decimals[i];
            TrimmedAmount trimmedAmount = amount.trim(decimals[i], 8);
            TrimmedAmount trimmedAmountOther = amountOther.trim(decimals[i], 8);
            TrimmedAmount trimmedSub = trimmedAmount - trimmedAmountOther;

            TrimmedAmount expectedTrimmedSub = packTrimmedAmount(
                uint64(3 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]
            );
            assert(expectedTrimmedSub == trimmedSub);
        }
    }

    function testSubOperatorZero() public pure {
        uint8[2] memory decimals = [18, 3];
        uint8[2] memory expectedDecimals = [8, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 0;
            TrimmedAmount trimmedAmount = amount.trim(decimals[i], 8);
            TrimmedAmount trimmedAmountOther = amountOther.trim(decimals[i], 8);
            TrimmedAmount trimmedSub = trimmedAmount - trimmedAmountOther;

            TrimmedAmount expectedTrimmedSub = packTrimmedAmount(
                uint64(5 * 10 ** uint64(expectedDecimals[i])), expectedDecimals[i]
            );
            assert(expectedTrimmedSub == trimmedSub);
        }
    }

    function testSubOperatorOverflow() public {
        uint8[2] memory decimals = [18, 3];

        for (uint8 i = 0; i < decimals.length; i++) {
            uint256 amount = 5 * 10 ** decimals[i];
            uint256 amountOther = 6 * 10 ** decimals[i];
            TrimmedAmount trimmedAmount = amount.trim(decimals[i], 8);
            TrimmedAmount trimmedAmountOther = amountOther.trim(decimals[i], 8);

            // arithmetic overflow
            vm.expectRevert(stdError.arithmeticError);
            trimmedAmount - trimmedAmountOther;
        }
    }

    function testDifferentDecimals() public {
        uint8 sourceDecimals = 18;
        uint8 targetDecimals = 6;
        uint256 amount = 5 * 10 ** sourceDecimals;

        TrimmedAmount trimmedAmount = amount.trim(sourceDecimals, 8);
        // trimmed to 8
        uint256 amountRoundTrip = trimmedAmount.untrim(targetDecimals);
        // untrim to 6
        uint256 expectedRoundTrip = 5 * 10 ** targetDecimals;

        assertEq(expectedRoundTrip, amountRoundTrip);
    }

    function testFuzz_AddOperatorOverload(TrimmedAmount a, TrimmedAmount b) public {
        vm.assume(a.getDecimals() == b.getDecimals());

        // check if the add operation reverts on an overflow.
        // if it overflows, discard the input
        uint256 largeSum = uint256(a.getAmount()) + uint256(b.getAmount());
        vm.assume(largeSum <= type(uint64).max);

        // check if the sum matches the expected sum if no overflow
        TrimmedAmount sum = a + b;
        TrimmedAmount expectedSum = add(a, b);

        assertEq(expectedSum.getAmount(), sum.getAmount());
        assertEq(expectedSum.getDecimals(), sum.getDecimals());
    }

    function testFuzz_SubOperatorOverload(TrimmedAmount a, TrimmedAmount b) public {
        vm.assume(a.getDecimals() == b.getDecimals());
        vm.assume(a.getAmount() >= b.getAmount());

        TrimmedAmount subAmt = a - b;
        TrimmedAmount expectedSub = sub(a, b);

        assertEq(expectedSub.getAmount(), subAmt.getAmount());
        assertEq(expectedSub.getDecimals(), subAmt.getDecimals());
    }

    function testFuzz_EqOperatorOverload(TrimmedAmount a, TrimmedAmount b) public {
        bool isEqual = a == b;
        bool expectedIsEqual = eq(a, b);

        assertEq(expectedIsEqual, isEqual);
    }

    function testFuzz_GtOperatorOverload(TrimmedAmount a, TrimmedAmount b) public {
        vm.assume(a.getDecimals() == b.getDecimals());
        bool isGt = a > b;
        bool expectedIsGt = gt(a, b);

        assertEq(expectedIsGt, isGt);
    }

    function testFuzz_LtOperatorOverload(TrimmedAmount a, TrimmedAmount b) public {
        vm.assume(a.getDecimals() == b.getDecimals());
        bool isLt = a > b;
        bool expectedIsLt = gt(a, b);

        assertEq(expectedIsLt, isLt);
    }
}

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

    // invariant: forall (x: uint256, y: uint8, z: uint8),
    //            (x <= type(uint64).max, y <= z)
    //                    => (x.trim(x, 8).untrim(y) == x)
    function testFuzz_trimIsLeftInverse(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) public {
        uint256 amt = bound(amount, 1, type(uint64).max);
        vm.assume(fromDecimals <= 50);
        vm.assume(toDecimals <= 50);

        // NOTE: this is guaranteeed by trimming
        vm.assume(fromDecimals <= 8 && fromDecimals <= toDecimals);

        // initialize TrimmedAmount
        TrimmedAmount memory trimmedAmount = TrimmedAmount(uint64(amt), fromDecimals);

        // trimming is left inverse of trimming
        uint256 amountUntrimmed = trimmedAmount.untrim(toDecimals);
        TrimmedAmount memory amountRoundTrip = amountUntrimmed.trim(toDecimals, fromDecimals);

        assertEq(trimmedAmount.amount, amountRoundTrip.amount);
    }

    // FUZZ TESTS

    // invariant: forall (TrimmedAmount a, TrimmedAmount b)
    //            a.saturatingAdd(b).amount <= type(uint64).max
    function testFuzz_saturatingAddDoesNotOverflow(
        TrimmedAmount memory a,
        TrimmedAmount memory b
    ) public {
        vm.assume(a.decimals == b.decimals);

        TrimmedAmount memory c = a.saturatingAdd(b);

        // decimals should always be the same, else revert
        assertEq(c.decimals, a.decimals);

        // amount should never overflow
        assertLe(c.amount, type(uint64).max);
        // amount should never underflow
        assertGe(c.amount, 0);
    }

    // NOTE: above the TRIMMED_DECIMALS threshold will always get trimmed to TRIMMED_DECIMALS
    // or trimmed to the number of decimals on the recipient chain.
    // this tests for inputs with decimals > TRIMMED_DECIMALS
    function testFuzz_SubOperatorZeroAboveThreshold(uint256 amt, uint8 decimals) public pure {
        decimals = uint8(bound(decimals, 8, 18));
        uint256 maxAmt = (type(uint64).max) / (10 ** decimals);
        vm.assume(amt < maxAmt);

        uint256 amount = amt * (10 ** decimals);
        uint256 amountOther = 0;
        TrimmedAmount memory trimmedAmount = amount.trim(decimals, 8);
        TrimmedAmount memory trimmedAmountOther = amountOther.trim(decimals, 8);

        TrimmedAmount memory trimmedSub = trimmedAmount.sub(trimmedAmountOther);

        TrimmedAmount memory expectedTrimmedSub = TrimmedAmount(uint64(amt * (10 ** 8)), 8);
        assert(expectedTrimmedSub.eq(trimmedSub));
    }

    function testFuzz_SubOperatorWillOverflow(
        uint8 decimals,
        uint256 amtLeft,
        uint256 amtRight
    ) public {
        decimals = uint8(bound(decimals, 8, 18));
        uint256 maxAmt = (type(uint64).max) / (10 ** decimals);
        vm.assume(amtRight < maxAmt);
        vm.assume(amtLeft < amtRight);

        uint256 amountLeft = amtLeft * (10 ** decimals);
        uint256 amountRight = amtRight * (10 ** decimals);
        TrimmedAmount memory trimmedAmount = amountLeft.trim(decimals, 8);
        TrimmedAmount memory trimmedAmountOther = amountRight.trim(decimals, 8);

        vm.expectRevert();
        trimmedAmount.sub(trimmedAmountOther);
    }

    // NOTE: above the TRIMMED_DECIMALS threshold will always get trimmed to TRIMMED_DECIMALS
    // or trimmed to the number of decimals on the recipient chain.
    // this tests for inputs with decimals > TRIMMED_DECIMALS
    function testFuzz_AddOperatorZeroAboveThreshold(uint256 amt, uint8 decimals) public pure {
        decimals = uint8(bound(decimals, 8, 18));
        uint256 maxAmt = (type(uint64).max) / (10 ** decimals);
        vm.assume(amt < maxAmt);

        uint256 amount = amt * (10 ** decimals);
        uint256 amountOther = 0;
        TrimmedAmount memory trimmedAmount = amount.trim(decimals, 8);
        TrimmedAmount memory trimmedAmountOther = amountOther.trim(decimals, 8);

        TrimmedAmount memory trimmedSum = trimmedAmount.add(trimmedAmountOther);

        TrimmedAmount memory expectedTrimmedSum = TrimmedAmount(uint64(amt * (10 ** 8)), 8);
        assert(expectedTrimmedSum.eq(trimmedSum));
    }
}

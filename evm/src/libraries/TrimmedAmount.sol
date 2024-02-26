// SPDX-License-Identifier: Apache 2
/// @dev TrimmedAmount is a utility library to handle token amounts with different decimals
pragma solidity >=0.8.8 <0.9.0;

struct TrimmedAmount {
    uint64 amount;
    uint8 decimals;
}

function minUint8(uint8 a, uint8 b) pure returns (uint8) {
    return a < b ? a : b;
}

library TrimmedAmountLib {
    uint8 constant TRIMMED_DECIMALS = 8;

    error AmountTooLarge(uint256 amount);
    error NumberOfDecimalsNotEqual(uint8 decimals, uint8 decimalsOther);

    function unwrap(TrimmedAmount memory a) internal pure returns (uint64, uint8) {
        return (a.amount, a.decimals);
    }

    function getAmount(TrimmedAmount memory a) internal pure returns (uint64) {
        return a.amount;
    }

    function getDecimals(TrimmedAmount memory a) internal pure returns (uint8) {
        return a.decimals;
    }

    function eq(TrimmedAmount memory a, TrimmedAmount memory b) internal pure returns (bool) {
        return a.amount == b.amount && a.decimals == b.decimals;
    }

    function gt(TrimmedAmount memory a, TrimmedAmount memory b) internal pure returns (bool) {
        // on initialization
        if (isZero(b) && !isZero(a)) {
            return true;
        }
        if (isZero(a) && !isZero(b)) {
            return false;
        }

        if (a.decimals != b.decimals) {
            revert NumberOfDecimalsNotEqual(a.decimals, b.decimals);
        }

        return a.amount > b.amount;
    }

    function lt(TrimmedAmount memory a, TrimmedAmount memory b) internal pure returns (bool) {
        // on initialization
        if (isZero(b) && !isZero(a)) {
            return false;
        }
        if (isZero(a) && !isZero(b)) {
            return true;
        }

        if (a.decimals != b.decimals) {
            revert NumberOfDecimalsNotEqual(a.decimals, b.decimals);
        }

        return a.amount < b.amount;
    }

    function isZero(TrimmedAmount memory a) internal pure returns (bool) {
        return (a.amount == 0 && a.decimals == 0);
    }

    function sub(
        TrimmedAmount memory a,
        TrimmedAmount memory b
    ) internal pure returns (TrimmedAmount memory) {
        // on initialization
        if (isZero(b)) {
            return a;
        }

        if (a.decimals != b.decimals) {
            revert NumberOfDecimalsNotEqual(a.decimals, b.decimals);
        }

        return TrimmedAmount(a.amount - b.amount, a.decimals);
    }

    function add(
        TrimmedAmount memory a,
        TrimmedAmount memory b
    ) internal pure returns (TrimmedAmount memory) {
        // on initialization
        if (isZero(a)) {
            return b;
        }

        if (isZero(b)) {
            return a;
        }

        if (a.decimals != b.decimals) {
            revert NumberOfDecimalsNotEqual(a.decimals, b.decimals);
        }
        return TrimmedAmount(a.amount + b.amount, a.decimals);
    }

    function min(
        TrimmedAmount memory a,
        TrimmedAmount memory b
    ) public pure returns (TrimmedAmount memory) {
        // on initialization
        if (isZero(a) && !isZero(b)) {
            return a;
        }
        if (isZero(b) && !isZero(a)) {
            return b;
        }

        if (a.decimals != b.decimals) {
            revert NumberOfDecimalsNotEqual(a.decimals, b.decimals);
        }

        return a.amount < b.amount ? a : b;
    }

    /// @dev scale the amount from original decimals to target decimals (base 10)
    function scale(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        }

        if (fromDecimals > toDecimals) {
            return amount / (10 ** (fromDecimals - toDecimals));
        } else {
            return amount * (10 ** (toDecimals - fromDecimals));
        }
    }

    function trim(uint256 amt, uint8 fromDecimals) internal pure returns (TrimmedAmount memory) {
        uint8 toDecimals = minUint8(TRIMMED_DECIMALS, fromDecimals);
        uint256 amountScaled = scale(amt, fromDecimals, toDecimals);

        // NOTE: amt after trimming must fit into uint64 (that's the point of
        // trimming, as Solana only supports uint64 for token amts)
        if (amountScaled > type(uint64).max) {
            revert AmountTooLarge(amt);
        }
        return TrimmedAmount(uint64(amountScaled), toDecimals);
    }

    function untrim(TrimmedAmount memory amt, uint8 toDecimals) internal pure returns (uint256) {
        (uint256 deNorm, uint8 fromDecimals) = unwrap(amt);
        uint256 amountScaled = scale(deNorm, fromDecimals, toDecimals);

        return amountScaled;
    }
}

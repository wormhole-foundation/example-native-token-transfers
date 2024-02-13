// SPDX-License-Identifier: Apache 2
/// @dev NormalizedAmount is a utility library to handle token amounts with different decimals
pragma solidity >=0.8.8 <0.9.0;

struct NormalizedAmount {
    uint64 amount;
    uint8 decimals;
}

library NormalizedAmountLib {
    uint8 constant NORMALIZED_DECIMALS = 8;

    error AmountTooLarge(uint256 amount);
    error NumberOfDecimalsNotEqual(uint8 decimals, uint8 decimalsOther);

    function unwrap(NormalizedAmount memory a) internal pure returns (uint64, uint8) {
        return (a.amount, a.decimals);
    }

    function getAmount(NormalizedAmount memory a) internal pure returns (uint64) {
        return a.amount;
    }

    function getDecimals(NormalizedAmount memory a) internal pure returns (uint8) {
        return a.decimals;
    }

    function eq(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) internal pure returns (bool) {
        return a.amount == b.amount && a.decimals == b.decimals;
    }

    function gt(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) internal pure returns (bool) {
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

    function lt(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) internal pure returns (bool) {
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

    function isZero(NormalizedAmount memory a) internal pure returns (bool) {
        return (a.amount == 0 && a.decimals == 0);
    }

    function sub(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) internal pure returns (NormalizedAmount memory) {
        // on initialization
        if (isZero(b)) {
            return a;
        }

        if (a.decimals != b.decimals) {
            revert NumberOfDecimalsNotEqual(a.decimals, b.decimals);
        }

        return NormalizedAmount(a.amount - b.amount, a.decimals);
    }

    function add(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) internal pure returns (NormalizedAmount memory) {
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
        return NormalizedAmount(a.amount + b.amount, a.decimals);
    }

    function min(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) public pure returns (NormalizedAmount memory) {
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

    function minDecimals(uint8 toDecimals, uint8 fromDecimals) internal pure returns (uint8) {
        return toDecimals < fromDecimals ? toDecimals : fromDecimals;
    }

    /// @dev scale the amount from origDecimals to normDecimals (base 10)
    function scalingFactor(
        uint8 origDecimals,
        uint8 normDecimals
    ) internal pure returns (uint256) {
        if (origDecimals > normDecimals) {
            return 10 ** (origDecimals - normDecimals);
        } else {
            return 1;
        }
    }

    function normalize(
        uint256 amt,
        uint8 fromDecimals
    ) internal pure returns (NormalizedAmount memory) {
        uint8 toDecimals = minDecimals(NORMALIZED_DECIMALS, fromDecimals);
        amt /= scalingFactor(fromDecimals, toDecimals);

        // NOTE: amt after normalization must fit into uint64 (that's the point of
        // normalization, as Solana only supports uint64 for token amts)
        if (amt > type(uint64).max) {
            revert AmountTooLarge(amt);
        }
        return NormalizedAmount(uint64(amt), toDecimals);
    }

    function denormalize(
        NormalizedAmount memory amt,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        (uint256 deNorm, uint8 dec) = unwrap(amt);
        deNorm *= scalingFactor(toDecimals, dec);

        return deNorm;
    }
}
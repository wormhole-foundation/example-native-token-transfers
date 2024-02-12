/// @dev NormalizedAmount is a utility library to handle token amounts with different decimals
// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

struct NormalizedAmount {
    uint64 amount;
    uint8 decimals;
}

library NormalizedAmountLib {
    uint8 constant NORMALIZED_DECIMALS = 8;

    error AmountTooLarge(uint256 amount);
    error NumberOfDecimalsNotEqual(uint8 decimals, uint8 decimalsOther);

    function wrap(uint64 amt, uint8 dec) internal pure returns (NormalizedAmount memory) {
        return NormalizedAmount(amt, dec);
    }

    function unwrap(NormalizedAmount memory a) internal pure returns (uint64, uint8) {
        return (a.amount, a.decimals);
    }

    function getAmount(NormalizedAmount memory a) internal pure returns (uint64) {
        return a.amount;
    }

    function getDecimals(NormalizedAmount memory a) internal pure returns (uint8) {
        return a.decimals;
    }

    function gt(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) internal pure returns (bool) {
        if (a.decimals != b.decimals) {
            revert NumberOfDecimalsNotEqual(a.decimals, b.decimals);
        }
        return a.amount > b.amount;
    }

    function lt(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) internal pure returns (bool) {
        if (a.decimals != b.decimals) {
            revert NumberOfDecimalsNotEqual(a.decimals, b.decimals);
        }
        return a.amount < b.amount;
    }

    function sub(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) internal pure returns (NormalizedAmount memory) {
        if (a.decimals != b.decimals) {
            revert NumberOfDecimalsNotEqual(a.decimals, b.decimals);
        }

        return wrap(a.amount - b.amount, a.decimals);
    }

    function add(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) internal pure returns (NormalizedAmount memory) {
        if (a.decimals != b.decimals) {
            revert NumberOfDecimalsNotEqual(a.decimals, b.decimals);
        }
        return wrap(a.amount + b.amount, a.decimals);
    }

    function min(
        NormalizedAmount memory a,
        NormalizedAmount memory b
    ) public pure returns (NormalizedAmount memory) {
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
        return wrap(uint64(amt), toDecimals);
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

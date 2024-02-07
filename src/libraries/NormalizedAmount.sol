// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

type NormalizedAmount is uint64;

using {gt as >, lt as <, sub as -, add as +, div, min, unwrap} for NormalizedAmount global;

function gt(NormalizedAmount a, NormalizedAmount b) pure returns (bool) {
    return NormalizedAmount.unwrap(a) > NormalizedAmount.unwrap(b);
}

function lt(NormalizedAmount a, NormalizedAmount b) pure returns (bool) {
    return NormalizedAmount.unwrap(a) < NormalizedAmount.unwrap(b);
}

function sub(NormalizedAmount a, NormalizedAmount b) pure returns (NormalizedAmount) {
    return NormalizedAmount.wrap(NormalizedAmount.unwrap(a) - NormalizedAmount.unwrap(b));
}

function add(NormalizedAmount a, NormalizedAmount b) pure returns (NormalizedAmount) {
    return NormalizedAmount.wrap(NormalizedAmount.unwrap(a) + NormalizedAmount.unwrap(b));
}

function div(NormalizedAmount a, uint64 b) pure returns (NormalizedAmount) {
    return NormalizedAmount.wrap(NormalizedAmount.unwrap(a) / b);
}

function min(NormalizedAmount a, NormalizedAmount b) pure returns (NormalizedAmount) {
    return a > b ? b : a;
}

function unwrap(NormalizedAmount a) pure returns (uint64) {
    return NormalizedAmount.unwrap(a);
}

library NormalizedAmountLib {
    error AmountTooLarge(uint256 amount);

    function normalize(uint256 amount, uint8 decimals) internal pure returns (NormalizedAmount) {
        if (decimals > 8) {
            amount /= 10 ** (decimals - 8);
        }
        // amount after normalization must fit into uint64 (that's the point of
        // normalization, as Solana only supports uint64 for token amounts)
        if (amount > type(uint64).max) {
            revert AmountTooLarge(amount);
        }
        return NormalizedAmount.wrap(uint64(amount));
    }

    function denormalize(NormalizedAmount amount, uint8 decimals) internal pure returns (uint256) {
        uint256 denormalized = NormalizedAmount.unwrap(amount);
        if (decimals > 8) {
            denormalized *= 10 ** (decimals - 8);
        }
        return denormalized;
    }
}

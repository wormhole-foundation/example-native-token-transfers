// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.0 <0.9.0;

type NormalizedAmount is uint64;

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

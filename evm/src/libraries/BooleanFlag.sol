// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

/// @dev A boolean flag represented as a uint256 (the native EVM word size)
/// This is more gas efficient when setting and clearing the flag
type BooleanFlag is uint256;

library BooleanFlagLib {
    /// @notice Error when boolean flag is not 0 or 1
    /// @dev Selector: 0x837017c0.
    /// @param value The value of the boolean flag
    error InvalidBoolValue(BooleanFlag value);

    uint256 constant FALSE = 0;
    uint256 constant TRUE = 1;

    function isSet(
        BooleanFlag value
    ) internal pure returns (bool) {
        return BooleanFlag.unwrap(value) == TRUE;
    }

    function toBool(
        BooleanFlag value
    ) internal pure returns (bool) {
        if (BooleanFlag.unwrap(value) == 0) return false;
        if (BooleanFlag.unwrap(value) == 1) return true;

        revert InvalidBoolValue(value);
    }

    function toWord(
        bool value
    ) internal pure returns (BooleanFlag) {
        if (value) {
            return BooleanFlag.wrap(TRUE);
        } else {
            return BooleanFlag.wrap(FALSE);
        }
    }
}

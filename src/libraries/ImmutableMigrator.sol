// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

abstract contract ImmutableMigrator {
    struct _Bool {
        bool value;
    }

    bytes32 public constant MIGRATES_IMMUTABLES_SLOT =
        bytes32(uint256(keccak256("ntt.migratesImmutables")) - 1);

    function _getMigratesImmutablesStorage() internal pure returns (_Bool storage $) {
        uint256 slot = uint256(MIGRATES_IMMUTABLES_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function getMigratesImmutables() public view returns (bool) {
        return _getMigratesImmutablesStorage().value;
    }

    function _setMigratesImmutables(bool value) internal {
        _getMigratesImmutablesStorage().value = value;
    }
}

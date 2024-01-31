// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

abstract contract ImmutableMigrator {
    bool public migratesImmutables;

    function _setMigratesImmutables(bool value) internal {
        migratesImmutables = value;
    }
}

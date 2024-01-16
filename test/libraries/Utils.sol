// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

library Utils {
    /// @dev Given a log of account accesses (captured by
    ///      vm.startStateDiffRecording), returns whether a storage slot was written.
    ///      This is useful for testing that a contract's constructor does not
    ///      write to storage (and is therefore suitable as a constructor for an
    ///      implementation behind an upgradable proxy.)
    function writesToStorage(VmSafe.AccountAccess[] memory accesses) public pure returns (bool) {
        for (uint256 j = 0; j < accesses.length; j++) {
            VmSafe.AccountAccess memory access = accesses[j];
            for (uint256 i = 0; i < access.storageAccesses.length; i++) {
                if (access.storageAccesses[i].isWrite) {
                    return true;
                }
            }
        }
        return false;
    }
}

contract WritesToStorage {
    uint256 a;

    constructor() {
        a = 10;
    }
}

contract DoesntWriteToStorage {}

contract UtilsTest is Test {
    function test_writesToStorage() public {
        vm.startStateDiffRecording();

        new WritesToStorage();

        assert(Utils.writesToStorage(vm.stopAndReturnStateDiff()));
    }

    function test_doesntWriteToStorage() public {
        vm.startStateDiffRecording();

        new DoesntWriteToStorage();

        assert(!Utils.writesToStorage(vm.stopAndReturnStateDiff()));
    }
}

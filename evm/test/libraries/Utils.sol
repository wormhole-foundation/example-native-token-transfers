// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {VmSafe, Vm} from "forge-std/Vm.sol";

import "../../src/libraries/external/Initializable.sol";

library Utils {
    /// @dev Given a log of account accesses (captured by
    ///      vm.startStateDiffRecording), returns whether a storage slot was written.
    ///      This is useful for testing that a contract's constructor does not
    ///      write to storage (and is therefore suitable as a constructor for an
    ///      implementation behind an upgradable proxy.)
    function assertSafeUpgradeableConstructor(
        VmSafe.AccountAccess[] memory accesses
    ) public pure {
        bytes32 INITIALIZABLE_STORAGE =
            0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

        bool disabledInitializer = false;

        for (uint256 j = 0; j < accesses.length; j++) {
            VmSafe.AccountAccess memory access = accesses[j];
            for (uint256 i = 0; i < access.storageAccesses.length; i++) {
                if (access.storageAccesses[i].isWrite) {
                    if (access.storageAccesses[i].slot == INITIALIZABLE_STORAGE) {
                        disabledInitializer = true;
                    } else {
                        revert("upgradeable implementation constructor wrote storage slot");
                    }
                }
            }
        }

        if (!disabledInitializer) {
            revert("upgradeable implementation constructor didn't disable initializers");
        }
    }

    // Fetches the queued transfer digests from the logs when an inbound transfer is queued
    function fetchQueuedTransferDigestsFromLogs(
        Vm.Log[] memory logs
    ) public pure returns (bytes32[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("InboundTransferQueued(bytes32)")) {
                count += 1;
            }
        }

        // create log array to save published messages
        bytes32[] memory published = new bytes32[](count);

        uint256 publishedIndex = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("InboundTransferQueued(bytes32)")) {
                published[publishedIndex] = bytes32(logs[i].data);
                // console.logBytes(logs[i].data);
                publishedIndex += 1;
            }
        }

        return published;
    }
}

contract WritesToStorage {
    uint256 a;

    constructor() {
        a = 10;
    }
}

contract DoesntDisableInitializer {}

contract SafeConstructor is Initializable {
    constructor() {
        _disableInitializers();
    }
}

contract UtilsTest is Test {
    function test_writesToStorage() public {
        vm.startStateDiffRecording();

        new WritesToStorage();

        vm.expectRevert();
        Utils.assertSafeUpgradeableConstructor(vm.stopAndReturnStateDiff());
    }

    function test_doesntDisableInitializer() public {
        vm.startStateDiffRecording();

        new DoesntDisableInitializer();

        vm.expectRevert();
        Utils.assertSafeUpgradeableConstructor(vm.stopAndReturnStateDiff());
    }

    function test_safeConstructor() public {
        vm.startStateDiffRecording();

        new SafeConstructor();

        Utils.assertSafeUpgradeableConstructor(vm.stopAndReturnStateDiff());
    }
}

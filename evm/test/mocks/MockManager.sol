// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "../../src/Manager.sol";

contract MockManagerContract is Manager {
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration
    ) Manager(token, mode, chainId, rateLimitDuration) {}

    /// We create a dummy storage variable here with standard solidity slot assignment.
    /// Then we check that its assigned slot is 0, i.e. that the super contract doesn't
    /// define any storage variables (and instead uses deterministic slots).
    /// See `test_noAutomaticSlot` below.
    uint256 my_slot;

    function lastSlot() public pure returns (bytes32 result) {
        assembly ("memory-safe") {
            result := my_slot.slot
        }
    }
}

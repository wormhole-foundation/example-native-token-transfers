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

    function getOutboundLimitParams() public pure returns (RateLimitParams memory) {
        return _getOutboundLimitParams();
    }

    function getInboundLimitParams(uint16 chainId_) public view returns (RateLimitParams memory) {
        return _getInboundLimitParams(chainId_);
    }
}

contract MockManagerMigrateBasic is Manager {
    // Call the parents constructor
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration
    ) Manager(token, mode, chainId, rateLimitDuration) {}

    function _migrate() internal view override {
        _checkThresholdInvariants();
        _checkTransceiversInvariants();
        revert("Proper migrate called");
    }
}

contract MockManagerImmutableCheck is Manager {
    // Call the parents constructor
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration
    ) Manager(token, mode, chainId, rateLimitDuration) {}
}

contract MockManagerImmutableRemoveCheck is Manager {
    // Call the parents constructor
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration
    ) Manager(token, mode, chainId, rateLimitDuration) {}

    // Turns on the capability to EDIT the immutables
    function _migrate() internal override {
        _setMigratesImmutables(true);
    }
}

contract MockManagerStorageLayoutChange is Manager {
    address a;
    address b;
    address c;

    // Call the parents constructor
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration
    ) Manager(token, mode, chainId, rateLimitDuration) {}

    function setData() public {
        a = address(0x1);
        b = address(0x2);
        c = address(0x3);
    }
}

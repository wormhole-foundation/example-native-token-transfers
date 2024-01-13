// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "forge-std/Test.sol";

import "../src/EndpointManagerStandalone.sol";

// @dev A non-abstract EndpointManager contract
contract EndpointManagerContract is EndpointManagerStandalone {
    constructor(
        address token,
        bool isLockingMode,
        uint16 chainId
    ) EndpointManagerStandalone(token, isLockingMode, chainId) {}
}

contract TestEndpointManager is Test {
    EndpointManagerStandalone endpointManager;

    function test_countSetBits() public {
        assertEq(endpointManager.countSetBits(5), 2);
        assertEq(endpointManager.countSetBits(0), 0);
        assertEq(endpointManager.countSetBits(15), 4);
        assertEq(endpointManager.countSetBits(16), 1);
        assertEq(endpointManager.countSetBits(65535), 16);
    }

    function setUp() public {
        endpointManager = new EndpointManagerContract(address(0), false, 0);
        endpointManager.initialize();
        // deploy sample token contract
        // deploy wormhole contract
        // wormhole = deployWormholeForTest();
        // deploy endpoint contracts
        // instantiate endpoint manager contract
        // endpointManager = new EndpointManagerContract();
    }
}

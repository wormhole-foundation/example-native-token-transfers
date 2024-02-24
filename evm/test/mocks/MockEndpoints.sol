// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "../../src/WormholeEndpoint.sol";

contract MockWormholeEndpointContract is WormholeEndpoint {
    constructor(
        address manager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr,
        uint8 _consistencyLevel
    )
        WormholeEndpoint(
            manager,
            wormholeCoreBridge,
            wormholeRelayerAddr,
            specialRelayerAddr,
            _consistencyLevel
        )
    {}

    /// @dev Override the [`transferOwnership`] method from OwnableUpgradeable
    /// to ensure owner of this contract is in sync with the onwer of the Manager contract.
    function transferOwnership(address newOwner) public view override onlyOwner {
        revert CannotTransferEndpointOwnership(owner(), newOwner);
    }
}

contract MockWormholeEndpointMigrateBasic is WormholeEndpoint {
    constructor(
        address manager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr,
        uint8 _consistencyLevel
    )
        WormholeEndpoint(
            manager,
            wormholeCoreBridge,
            wormholeRelayerAddr,
            specialRelayerAddr,
            _consistencyLevel
        )
    {}

    function _migrate() internal pure override {
        revert("Proper migrate called");
    }
}

contract MockWormholeEndpointImmutableAllow is WormholeEndpoint {
    constructor(
        address manager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr,
        uint8 _consistencyLevel
    )
        WormholeEndpoint(
            manager,
            wormholeCoreBridge,
            wormholeRelayerAddr,
            specialRelayerAddr,
            _consistencyLevel
        )
    {}

    // Allow for the immutables to be migrated
    function _migrate() internal override {
        _setMigratesImmutables(true);
    }
}

contract MockWormholeEndpointLayoutChange is WormholeEndpoint {
    address a;
    address b;
    address c;

    // Call the parents constructor
    constructor(
        address manager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr,
        uint8 _consistencyLevel
    )
        WormholeEndpoint(
            manager,
            wormholeCoreBridge,
            wormholeRelayerAddr,
            specialRelayerAddr,
            _consistencyLevel
        )
    {}

    function setData() public {
        a = address(0x1);
        b = address(0x2);
        c = address(0x3);
    }
}

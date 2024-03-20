// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "../../src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";

contract MockWormholeTransceiverContract is WormholeTransceiver {
    constructor(
        address nttManager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr,
        uint8 _consistencyLevel,
        uint256 _gasLimit,
        ManagerType _managerType
    )
        WormholeTransceiver(
            nttManager,
            wormholeCoreBridge,
            wormholeRelayerAddr,
            specialRelayerAddr,
            _consistencyLevel,
            _gasLimit,
            _managerType
        )
    {}

    /// @dev Override the [`transferOwnership`] method from OwnableUpgradeable
    /// to ensure owner of this contract is in sync with the onwer of the NttManager contract.
    function transferOwnership(address newOwner) public view override onlyOwner {
        revert CannotTransferTransceiverOwnership(owner(), newOwner);
    }
}

contract MockWormholeTransceiverMigrateBasic is WormholeTransceiver {
    constructor(
        address nttManager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr,
        uint8 _consistencyLevel,
        uint256 _gasLimit,
        ManagerType _managerType
    )
        WormholeTransceiver(
            nttManager,
            wormholeCoreBridge,
            wormholeRelayerAddr,
            specialRelayerAddr,
            _consistencyLevel,
            _gasLimit,
            _managerType
        )
    {}

    function _migrate() internal pure override {
        revert("Proper migrate called");
    }
}

contract MockWormholeTransceiverImmutableAllow is WormholeTransceiver {
    constructor(
        address nttManager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr,
        uint8 _consistencyLevel,
        uint256 _gasLimit,
        ManagerType _managerType
    )
        WormholeTransceiver(
            nttManager,
            wormholeCoreBridge,
            wormholeRelayerAddr,
            specialRelayerAddr,
            _consistencyLevel,
            _gasLimit,
            _managerType
        )
    {}

    // Allow for the immutables to be migrated
    function _migrate() internal override {
        _setMigratesImmutables(true);
    }
}

contract MockWormholeTransceiverLayoutChange is WormholeTransceiver {
    address a;
    address b;
    address c;

    // Call the parents constructor
    constructor(
        address nttManager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr,
        uint8 _consistencyLevel,
        uint256 _gasLimit,
        ManagerType _managerType
    )
        WormholeTransceiver(
            nttManager,
            wormholeCoreBridge,
            wormholeRelayerAddr,
            specialRelayerAddr,
            _consistencyLevel,
            _gasLimit,
            _managerType
        )
    {}

    function setData() public {
        a = address(0x1);
        b = address(0x2);
        c = address(0x3);
    }
}

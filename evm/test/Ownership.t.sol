// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "./mocks/MockNttManager.sol";
import "../src/interfaces/IManagerBase.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DummyTransceiver} from "./NttManager.t.sol";
import {DummyToken} from "./NttManager.t.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";

contract OwnershipTests is Test {
    NttManager nttManager;
    uint16 constant chainId = 7;

    function setUp() public {
        IWormhole wormhole = IWormhole(0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78);
        DummyToken t = new DummyToken();
        vm.mockCall(
            address(wormhole),
            abi.encodeWithSelector(bytes4(keccak256("chainId()"))),
            abi.encode(chainId)
        );
        NttManager implementation = new MockNttManagerContract(
            address(t), IManagerBase.Mode.LOCKING, address(wormhole), 1 days, false
        );

        nttManager = MockNttManagerContract(address(new ERC1967Proxy(address(implementation), "")));
        nttManager.initialize();
    }

    function checkOwnership(DummyTransceiver e, address nttManagerOwner) public {
        address transceiverNttManager = e.getNttManagerOwner();
        assertEq(transceiverNttManager, nttManagerOwner);
    }

    /// transceiver retrieves the nttManager owner correctly
    function testTransceiverOwnership() public {
        // TODO: use setup_transceivers here
        DummyTransceiver e1 = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e1));
        nttManager.setThreshold(1);

        checkOwnership(e1, nttManager.owner());
    }
}

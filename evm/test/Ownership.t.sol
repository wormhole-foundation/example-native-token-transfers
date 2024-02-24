// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "./mocks/MockManager.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DummyTransceiver} from "./Manager.t.sol";
import {DummyToken} from "./Manager.t.sol";

contract OwnershipTests is Test {
    Manager manager;
    uint16 constant chainId = 7;

    function setUp() public {
        DummyToken t = new DummyToken();
        Manager implementation =
            new MockManagerContract(address(t), Manager.Mode.LOCKING, chainId, 1 days);

        manager = MockManagerContract(address(new ERC1967Proxy(address(implementation), "")));
        manager.initialize();
    }

    function checkOwnership(DummyTransceiver e, address managerOwner) public {
        address transceiverManager = e.getManagerOwner();
        assertEq(transceiverManager, managerOwner);
    }

    /// transceiver retrieves the manager owner correctly
    function testTransceiverOwnership() public {
        // TODO: use setup_transceivers here
        DummyTransceiver e1 = new DummyTransceiver(address(manager));
        manager.setTransceiver(address(e1));
        manager.setThreshold(1);

        checkOwnership(e1, manager.owner());
    }
}

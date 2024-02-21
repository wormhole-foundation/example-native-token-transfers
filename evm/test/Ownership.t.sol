// // SPDX-License-Identifier: Apache 2

// pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "./mocks/MockManager.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DummyEndpoint} from "./Manager.t.sol";
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

//     function checkOwnership(DummyEndpoint e, address managerOwner) public {
//         address endpointManager = e.getManagerOwner();
//         assertEq(endpointManager, managerOwner);
//     }

//     /// endpoint retrieves the manager owner correctly
//     function testEndpointOwnership() public {
//         // TODO: use setup_endpoints here
//         DummyEndpoint e1 = new DummyEndpoint(address(manager));
//         manager.setEndpoint(address(e1));
//         manager.setThreshold(1);

//         checkOwnership(e1, manager.owner());
//     }
// }

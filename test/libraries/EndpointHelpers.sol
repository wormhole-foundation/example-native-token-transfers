// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "../mocks/DummyEndpoint.sol";
import "../../src/ManagerStandalone.sol";

library EndpointHelpersLib {
    function setup_endpoints(ManagerStandalone manager)
        internal
        returns (DummyEndpoint, DummyEndpoint)
    {
        DummyEndpoint e1 = new DummyEndpoint(address(manager));
        DummyEndpoint e2 = new DummyEndpoint(address(manager));
        manager.setEndpoint(address(e1));
        manager.setEndpoint(address(e2));
        manager.setThreshold(2);
        return (e1, e2);
    }
}

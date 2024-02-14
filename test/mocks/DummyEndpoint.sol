// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "../../src/EndpointStandalone.sol";
import "../interfaces/IEndpointReceiver.sol";

contract DummyEndpoint is EndpointStandalone, IEndpointReceiver {
    constructor(address manager) EndpointStandalone(manager) {}

    function _quoteDeliveryPrice(uint16 /* recipientChain */ )
        internal
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        bytes memory payload
    ) internal override {
        // do nothing
    }

    function receiveMessage(bytes memory encodedMessage) external {
        EndpointStructs.ManagerMessage memory parsed =
            EndpointStructs.parseManagerMessage(encodedMessage);
        _deliverToManager(parsed);
    }

    function _parseEndpointMessage(bytes memory encoded)
        internal
        pure
        override
        returns (EndpointStructs.EndpointMessage memory endpointMessage)
    {}

    function parseMessageFromLogs(Vm.Log[] memory logs)
        public
        pure
        returns (uint16 recipientChain, bytes memory payload)
    {}
}

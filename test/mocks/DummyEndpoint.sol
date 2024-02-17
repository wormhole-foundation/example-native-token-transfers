// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "../../src/EndpointStandalone.sol";
import "../interfaces/IEndpointReceiver.sol";

contract DummyEndpoint is EndpointStandalone, IEndpointReceiver {
    uint16 constant SENDING_CHAIN_ID = 1;
    bytes4 constant TEST_ENDPOINT_PAYLOAD_PREFIX = 0x99455454;

    constructor(address manager) EndpointStandalone(manager) {}

    function _quoteDeliveryPrice(
        uint16, /* recipientChain */
        EndpointStructs.EndpointInstruction memory /* endpointInstruction */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        EndpointStructs.EndpointInstruction memory instruction,
        bytes memory payload
    ) internal override {
        // do nothing
    }

    function receiveMessage(bytes memory encodedMessage) external {
        EndpointStructs.EndpointMessage memory parsedEndpointMessage;
        EndpointStructs.ManagerMessage memory parsedManagerMessage;
        (parsedEndpointMessage, parsedManagerMessage) = EndpointStructs
            .parseEndpointAndManagerMessage(TEST_ENDPOINT_PAYLOAD_PREFIX, encodedMessage);
        _deliverToManager(
            SENDING_CHAIN_ID, parsedEndpointMessage.sourceManagerAddress, parsedManagerMessage
        );
    }

    function parseMessageFromLogs(Vm.Log[] memory logs)
        public
        pure
        returns (uint16 recipientChain, bytes memory payload)
    {}
}

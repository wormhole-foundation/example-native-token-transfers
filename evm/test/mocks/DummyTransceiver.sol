// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "../../src/Transceiver/Transceiver.sol";
import "../interfaces/ITransceiverReceiver.sol";

contract DummyTransceiver is Transceiver, ITransceiverReceiver {
    uint16 constant SENDING_CHAIN_ID = 1;
    bytes4 constant TEST_TRANSCEIVER_PAYLOAD_PREFIX = 0x99455454;

    constructor(address nttManager) Transceiver(nttManager) {}

    function _quoteDeliveryPrice(
        uint16, /* recipientChain */
        TransceiverStructs.TransceiverInstruction memory, /* transceiverInstruction */
        uint256 /* managerExecutionCost */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _sendMessage(
        uint16, /* recipientChain */
        uint256, /* deliveryPayment */
        uint256, /* managerExecutionCost */
        address, /* caller */
        bytes32, /* recipientNttManagerAddress */
        TransceiverStructs.TransceiverInstruction memory, /* instruction */
        bytes memory /* payload */
    ) internal override {
        // do nothing
    }

    function receiveMessage(bytes memory encodedMessage) external virtual {
        TransceiverStructs.TransceiverMessage memory parsedTransceiverMessage;
        TransceiverStructs.ManagerMessage memory parsedManagerMessage;
        (parsedTransceiverMessage, parsedManagerMessage) = TransceiverStructs
            .parseTransceiverAndManagerMessage(TEST_TRANSCEIVER_PAYLOAD_PREFIX, encodedMessage);
        _deliverToNttManager(
            SENDING_CHAIN_ID,
            parsedTransceiverMessage.sourceNttManagerAddress,
            parsedTransceiverMessage.recipientNttManagerAddress,
            parsedManagerMessage
        );
    }

    function parseMessageFromLogs(Vm.Log[] memory logs)
        public
        pure
        returns (uint16 recipientChain, bytes memory payload)
    {}
}

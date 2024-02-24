// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TransceiverStructs.sol";

interface ITransceiver {
    error CallerNotNttManager(address caller);
    error CannotRenounceTransceiverOwnership(address currentOwner);
    error CannotTransferTransceiverOwnership(address currentOwner, address newOwner);
    error UnexpectedRecipientNttManagerAddress(
        bytes32 recipientNttManagerAddress, bytes32 expectedRecipientNttManagerAddress
    );

    function quoteDeliveryPrice(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction memory instruction
    ) external view returns (uint256);

    function sendMessage(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction memory instruction,
        bytes memory nttManagerMessage,
        bytes32 recipientNttManagerAddress
    ) external payable;

    function upgrade(address newImplementation) external;

    function transferTransceiverOwnership(address newOwner) external;
}

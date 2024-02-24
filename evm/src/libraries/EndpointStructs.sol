// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "./NormalizedAmount.sol";

library EndpointStructs {
    using BytesParsing for bytes;
    using NormalizedAmountLib for NormalizedAmount;

    /// @notice Error thrown when the payload length exceeds the allowed maximum.
    /// @dev Selector 0xa3419691.
    /// @param size The size of the payload.
    error PayloadTooLong(uint256 size);

    /// @notice Error thrown when the prefix of an encoded message
    ///         does not match the expected value.
    /// @dev Selector 0x56d2569d.
    /// @param prefix The prefix that was found in the encoded message.
    error IncorrectPrefix(bytes4 prefix);
    error UnorderedInstructions();

    /// @dev Prefix for all NativeTokenTransfer payloads
    ///      This is 0x99'N''T''T'
    bytes4 constant NTT_PREFIX = 0x994E5454;

    /// @dev Message emitted and received by the manager contract.
    ///      The wire format is as follows:
    ///      - sequence - 8 bytes
    ///      - sender - 32 bytes
    ///      - payloadLength - 2 bytes
    ///      - payload - `payloadLength` bytes
    struct ManagerMessage {
        /// @notice unique sequence number
        uint64 sequence;
        /// @notice original message sender address.
        bytes32 sender;
        /// @notice payload that corresponds to the type.
        bytes payload;
    }

    function managerMessageDigest(
        uint16 sourceChainId,
        ManagerMessage memory m
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(sourceChainId, encodeManagerMessage(m)));
    }

    function encodeManagerMessage(ManagerMessage memory m)
        public
        pure
        returns (bytes memory encoded)
    {
        if (m.payload.length > type(uint16).max) {
            revert PayloadTooLong(m.payload.length);
        }
        uint16 payloadLength = uint16(m.payload.length);
        return abi.encodePacked(m.sequence, m.sender, payloadLength, m.payload);
    }

    /// @notice Parse a ManagerMessage.
    /// @param encoded The byte array corresponding to the encoded message
    /// @return managerMessage The parsed ManagerMessage struct.
    function parseManagerMessage(bytes memory encoded)
        public
        pure
        returns (ManagerMessage memory managerMessage)
    {
        uint256 offset = 0;
        (managerMessage.sequence, offset) = encoded.asUint64Unchecked(offset);
        (managerMessage.sender, offset) = encoded.asBytes32Unchecked(offset);
        uint256 payloadLength;
        (payloadLength, offset) = encoded.asUint16Unchecked(offset);
        (managerMessage.payload, offset) = encoded.sliceUnchecked(offset, payloadLength);
        encoded.checkLength(offset);
    }

    /// @dev Native Token Transfer payload.
    ///      The wire format is as follows:
    ///      - NTT_PREFIX - 4 bytes
    ///      - numDecimals - 1 byte
    ///      - amount - 8 bytes
    ///      - sourceToken - 32 bytes
    ///      - to - 32 bytes
    ///      - toChain - 2 bytes
    struct NativeTokenTransfer {
        /// @notice Amount being transferred (big-endian u64 and u8 for decimals)
        NormalizedAmount amount;
        /// @notice Source chain token address.
        bytes32 sourceToken;
        /// @notice Address of the recipient.
        bytes32 to;
        /// @notice Chain ID of the recipient
        uint16 toChain;
    }

    function encodeNativeTokenTransfer(NativeTokenTransfer memory m)
        public
        pure
        returns (bytes memory encoded)
    {
        NormalizedAmount memory transferAmount = m.amount;
        return abi.encodePacked(
            NTT_PREFIX,
            transferAmount.getDecimals(),
            transferAmount.getAmount(),
            m.sourceToken,
            m.to,
            m.toChain
        );
    }

    /// @dev Parse a NativeTokenTransfer.
    /// @param encoded The byte array corresponding to the encoded message
    /// @return nativeTokenTransfer The parsed NativeTokenTransfer struct.
    function parseNativeTokenTransfer(bytes memory encoded)
        public
        pure
        returns (NativeTokenTransfer memory nativeTokenTransfer)
    {
        uint256 offset = 0;
        bytes4 prefix;
        (prefix, offset) = encoded.asBytes4Unchecked(offset);
        if (prefix != NTT_PREFIX) {
            revert IncorrectPrefix(prefix);
        }

        uint8 numDecimals;
        (numDecimals, offset) = encoded.asUint8Unchecked(offset);
        uint64 amount;
        (amount, offset) = encoded.asUint64Unchecked(offset);
        nativeTokenTransfer.amount = NormalizedAmount(amount, numDecimals);

        (nativeTokenTransfer.sourceToken, offset) = encoded.asBytes32Unchecked(offset);
        (nativeTokenTransfer.to, offset) = encoded.asBytes32Unchecked(offset);
        (nativeTokenTransfer.toChain, offset) = encoded.asUint16Unchecked(offset);
        encoded.checkLength(offset);
    }

    /// @dev Message emitted by Endpoint implementations.
    ///      Each message includes an Endpoint-specified 4-byte prefix.
    ///      The wire format is as follows:
    ///      - prefix - 4 bytes
    ///      - sourceManagerAddress - 32 bytes
    ///      - recipientManagerAddress - 32 bytes
    ///      - managerPayloadLength - 2 bytes
    ///      - managerPayload - `managerPayloadLength` bytes
    ///      - endpointPayloadLength - 2 bytes
    ///      - endpointPayload - `endpointPayloadLength` bytes
    struct EndpointMessage {
        /// @notice Address of the Manager contract that emitted this message.
        bytes32 sourceManagerAddress;
        /// @notice Address of the Manager contract that receives this message.
        bytes32 recipientManagerAddress;
        /// @notice Payload provided to the Endpoint contract by the Manager contract.
        bytes managerPayload;
        /// @notice Optional payload that the endpoint can encode and use for its own message passing purposes.
        bytes endpointPayload;
    }


    // @notice Encodes an Endpoint message for communication between the
    //         Manager and the Endpoint.
    // @param m The EndpointMessage struct containing the message details.
    // @return encoded The byte array corresponding to the encoded message.
    // @custom:throw PayloadTooLong if the length of endpointId, managerPayload,
    //         or endpointPayload exceeds the allowed maximum.
    function encodeEndpointMessage(
        bytes4 prefix,
        EndpointMessage memory m
    ) public pure returns (bytes memory encoded) {
        if (m.managerPayload.length > type(uint16).max) {
            revert PayloadTooLong(m.managerPayload.length);
        }
        uint16 managerPayloadLength = uint16(m.managerPayload.length);

        if (m.endpointPayload.length > type(uint16).max) {
            revert PayloadTooLong(m.endpointPayload.length);
        }
        uint16 endpointPayloadLength = uint16(m.endpointPayload.length);

        return abi.encodePacked(
            prefix,
            m.sourceManagerAddress,
            m.recipientManagerAddress,
            managerPayloadLength,
            m.managerPayload,
            endpointPayloadLength,
            m.endpointPayload
        );
    }

    function buildAndEncodeEndpointMessage(
        bytes4 prefix,
        bytes32 sourceManagerAddress,
        bytes32 recipientManagerAddress,
        bytes memory managerMessage,
        bytes memory endpointPayload
    ) public pure returns (EndpointMessage memory, bytes memory) {
        EndpointMessage memory endpointMessage = EndpointMessage({
            sourceManagerAddress: sourceManagerAddress,
            recipientManagerAddress: recipientManagerAddress,
            managerPayload: managerMessage,
            endpointPayload: endpointPayload
        });
        bytes memory encoded = encodeEndpointMessage(prefix, endpointMessage);
        return (endpointMessage, encoded);
    }


    /// @dev Parses an encoded message and extracts information into an EndpointMessage struct.
    /// @param encoded The encoded bytes containing information about the EndpointMessage.
    /// @return endpointMessage The parsed EndpointMessage struct.
    /// @custom:throw IncorrectPrefix if the prefix of the encoded message does not
    ///         match the expected prefix.
    function parseEndpointMessage(
        bytes4 expectedPrefix,
        bytes memory encoded
    ) internal pure returns (EndpointMessage memory endpointMessage) {
        uint256 offset = 0;
        bytes4 prefix;

        (prefix, offset) = encoded.asBytes4Unchecked(offset);

        if (prefix != expectedPrefix) {
            revert IncorrectPrefix(prefix);
        }

        (endpointMessage.sourceManagerAddress, offset) = encoded.asBytes32Unchecked(offset);
        (endpointMessage.recipientManagerAddress, offset) = encoded.asBytes32Unchecked(offset);
        uint16 managerPayloadLength;
        (managerPayloadLength, offset) = encoded.asUint16Unchecked(offset);
        (endpointMessage.managerPayload, offset) =
            encoded.sliceUnchecked(offset, managerPayloadLength);
        uint16 endpointPayloadLength;
        (endpointPayloadLength, offset) = encoded.asUint16Unchecked(offset);
        (endpointMessage.endpointPayload, offset) =
            encoded.sliceUnchecked(offset, endpointPayloadLength);

        // Check if the entire byte array has been processed
        encoded.checkLength(offset);
    }

    /// @dev Parses the payload of an Endpoint message and returns
    ///      the parsed ManagerMessage struct.
    /// @param expectedPrefix The prefix that should be encoded in the manager message.
    /// @param payload The payload sent across the wire.
    function parseEndpointAndManagerMessage(
        bytes4 expectedPrefix,
        bytes memory payload
    ) public pure returns (EndpointMessage memory, ManagerMessage memory) {
        // parse the encoded message payload from the Endpoint
        EndpointMessage memory parsedEndpointMessage = parseEndpointMessage(expectedPrefix, payload);

        // parse the encoded message payload from the Manager
        ManagerMessage memory parsedManagerMessage =
            parseManagerMessage(parsedEndpointMessage.managerPayload);

        return (parsedEndpointMessage, parsedManagerMessage);
    }

    /// @dev Variable-length endpoint-specific instruction that can be passed by the caller to the manager.
    ///      The index field refers to the index of the registeredEndpoint that this instruction should be passed to.
    ///      The serialization format is:
    ///      - index - 1 byte
    ///      - payloadLength - 1 byte
    ///      - payload - `payloadLength` bytes
    struct EndpointInstruction {
        uint8 index;
        bytes payload;
    }

    function encodeEndpointInstruction(EndpointInstruction memory instruction)
        public
        pure
        returns (bytes memory)
    {
        if (instruction.payload.length > type(uint8).max) {
            revert PayloadTooLong(instruction.payload.length);
        }
        uint8 payloadLength = uint8(instruction.payload.length);
        return abi.encodePacked(instruction.index, payloadLength, instruction.payload);
    }

    function parseEndpointInstructionUnchecked(
        bytes memory encoded,
        uint256 offset
    ) public pure returns (EndpointInstruction memory instruction, uint256 nextOffset) {
        (instruction.index, nextOffset) = encoded.asUint8Unchecked(offset);
        uint8 instructionLength;
        (instructionLength, nextOffset) = encoded.asUint8Unchecked(nextOffset);
        (instruction.payload, nextOffset) = encoded.sliceUnchecked(nextOffset, instructionLength);
    }

    function parseEndpointInstructionChecked(bytes memory encoded)
        public
        pure
        returns (EndpointInstruction memory instruction)
    {
        uint256 offset = 0;
        (instruction, offset) = parseEndpointInstructionUnchecked(encoded, offset);
        encoded.checkLength(offset);
    }

    /// @dev Encode an array of multiple variable-length endpoint-specific instructions.
    ///      The serialization format is:
    ///      - instructionsLength - 1 byte
    ///      - `instructionsLength` number of serialized `EndpointInstruction` types.
    function encodeEndpointInstructions(EndpointInstruction[] memory instructions)
        public
        pure
        returns (bytes memory)
    {
        if (instructions.length > type(uint8).max) {
            revert PayloadTooLong(instructions.length);
        }
        uint256 instructionsLength = instructions.length;

        bytes memory encoded;
        for (uint256 i = 0; i < instructionsLength; i++) {
            bytes memory innerEncoded = encodeEndpointInstruction(instructions[i]);
            encoded = bytes.concat(encoded, innerEncoded);
        }
        return abi.encodePacked(uint8(instructionsLength), encoded);
    }

    function parseEndpointInstructions(
        bytes memory encoded,
        uint256 numEnabledEndpoints
    ) public pure returns (EndpointInstruction[] memory) {
        uint256 offset = 0;
        uint256 instructionsLength;
        (instructionsLength, offset) = encoded.asUint8Unchecked(offset);

        // We allocate an array with the length of the number of enabled endpoints
        // This gives us the flexibility to not have to pass instructions for endpoints that
        // don't need them
        EndpointInstruction[] memory instructions = new EndpointInstruction[](numEnabledEndpoints);

        uint256 lastIndex = 0;
        for (uint256 i = 0; i < instructionsLength; i++) {
            EndpointInstruction memory instruction;
            (instruction, offset) = parseEndpointInstructionUnchecked(encoded, offset);

            uint8 instructionIndex = instruction.index;

            // The instructions passed in have to be strictly increasing in terms of endpoint index
            if (i != 0 && instructionIndex <= lastIndex) {
                revert UnorderedInstructions();
            }
            lastIndex = instructionIndex;

            instructions[instructionIndex] = instruction;
        }

        encoded.checkLength(offset);

        return instructions;
    }

    struct EndpointInit {
        bytes4 endpointIdentifier;
        bytes32 managerAddress;
        uint8 managerMode;
        bytes32 tokenAddress;
        uint8 tokenDecimals;
    }

    function encodeEndpointInit(EndpointInit memory init) public pure returns (bytes memory) {
        return abi.encodePacked(
            init.endpointIdentifier,
            init.managerAddress,
            init.managerMode,
            init.tokenAddress,
            init.tokenDecimals
        );
    }

    function decodeEndpointInit(bytes memory encoded)
        public
        pure
        returns (EndpointInit memory init)
    {
        uint256 offset = 0;
        (init.endpointIdentifier, offset) = encoded.asBytes4Unchecked(offset);
        (init.managerAddress, offset) = encoded.asBytes32Unchecked(offset);
        (init.managerMode, offset) = encoded.asUint8Unchecked(offset);
        (init.tokenAddress, offset) = encoded.asBytes32Unchecked(offset);
        (init.tokenDecimals, offset) = encoded.asUint8Unchecked(offset);
        encoded.checkLength(offset);
    }

    struct EndpointRegistration {
        bytes4 endpointIdentifier;
        uint16 endpointChainId;
        bytes32 endpointAddress;
    }

    function encodeEndpointRegistration(EndpointRegistration memory registration)
        public
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            registration.endpointIdentifier,
            registration.endpointChainId,
            registration.endpointAddress
        );
    }

    function decodeEndpointRegistration(bytes memory encoded)
        public
        pure
        returns (EndpointRegistration memory registration)
    {
        uint256 offset = 0;
        (registration.endpointIdentifier, offset) = encoded.asBytes4Unchecked(offset);
        (registration.endpointChainId, offset) = encoded.asUint16Unchecked(offset);
        (registration.endpointAddress, offset) = encoded.asBytes32Unchecked(offset);
        encoded.checkLength(offset);
    }
}

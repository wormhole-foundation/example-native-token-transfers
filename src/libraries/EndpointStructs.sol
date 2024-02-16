// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "./NormalizedAmount.sol";

library EndpointStructs {
    using BytesParsing for bytes;
    using NormalizedAmountLib for NormalizedAmount;

    error PayloadTooLong(uint256 size);
    error IncorrectPrefix(bytes4 prefix);

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

    /*
     * @dev Parse a ManagerMessage.
     *
     * @params encoded The byte array corresponding to the encoded message
     */
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

    /*
     * @dev Parse a NativeTokenTransfer.
     *
     * @params encoded The byte array corresponding to the encoded message
     */
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
    ///      - managerPayloadLength - 2 bytes
    ///      - managerPayload - `managerPayloadLength` bytes
    ///      - endpointPayloadLength - 2 bytes
    ///      - endpointPayload - `endpointPayloadLength` bytes
    struct EndpointMessage {
        /// @notice Address of the Manager contract that emitted this message.
        bytes32 sourceManagerAddress;
        /// @notice Payload provided to the Endpoint contract by the Manager contract.
        bytes managerPayload;
        /// @notice Optional payload that the endpoint can encode and use for its own message passing purposes.
        bytes endpointPayload;
    }

    /*
     * @dev Encodes an Endpoint message for communication between the Manager and the Endpoint.
     *
     * @param m The EndpointMessage struct containing the message details.
     * @return encoded The byte array corresponding to the encoded message.
     * @throws PayloadTooLong if the length of endpointId, managerPayload, or endpointPayload exceeds the allowed maximum.
     */
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
            managerPayloadLength,
            m.managerPayload,
            endpointPayloadLength,
            m.endpointPayload
        );
    }

    function buildAndEncodeEndpointMessage(
        bytes4 prefix,
        bytes32 sourceManagerAddress,
        bytes memory managerMessage,
        bytes memory endpointPayload
    ) public pure returns (EndpointMessage memory, bytes memory) {
        EndpointMessage memory endpointMessage = EndpointMessage({
            sourceManagerAddress: sourceManagerAddress,
            managerPayload: managerMessage,
            endpointPayload: endpointPayload
        });
        bytes memory encoded = encodeEndpointMessage(prefix, endpointMessage);
        return (endpointMessage, encoded);
    }

    /*
    * @dev Parses an encoded message and extracts information into an EndpointMessage struct.
    *
    * @param encoded The encoded bytes containing information about the EndpointMessage.
    * @return endpointMessage The parsed EndpointMessage struct.
    * @throws IncorrectPrefix if the prefix of the encoded message does not match the expected prefix.
    */
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

    /// @dev Parses the payload of an Endpoint message and returns the parsed ManagerMessage struct.
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
}

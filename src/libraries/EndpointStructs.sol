// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "./NormalizedAmount.sol";

library EndpointStructs {
    using BytesParsing for bytes;

    error PayloadTooLong(uint256 size);
    error IncorrectPrefix(bytes4 prefix);

    /// @dev Prefix for all NativeTokenTransfer payloads
    ///      This is 0x99'N''T''T'
    bytes4 constant NTT_PREFIX = 0x994E5454;

    /// @dev Message emitted and received by the manager contract.
    ///      The wire format is as follows:
    ///      - chainId - 2 bytes
    ///      - sequence - 8 bytes
    ///      - sourceManager - 32 bytes
    ///      - sender - 32 bytes
    ///      - payloadLength - 2 bytes
    ///      - payload - `payloadLength` bytes
    struct ManagerMessage {
        /// @notice chainId that message originates from
        uint16 chainId;
        /// @notice unique sequence number
        uint64 sequence;
        /// @notice manager contract address that this message originates from.
        bytes32 sourceManager;
        /// @notice original message sender address.
        bytes32 sender;
        /// @notice payload that corresponds to the type.
        bytes payload;
    }

    function managerMessageDigest(ManagerMessage memory m) public pure returns (bytes32) {
        return keccak256(encodeManagerMessage(m));
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
        return abi.encodePacked(
            m.chainId, m.sequence, m.sourceManager, m.sender, payloadLength, m.payload
        );
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
        (managerMessage.chainId, offset) = encoded.asUint16Unchecked(offset);
        (managerMessage.sequence, offset) = encoded.asUint64Unchecked(offset);
        (managerMessage.sourceManager, offset) = encoded.asBytes32Unchecked(offset);
        (managerMessage.sender, offset) = encoded.asBytes32Unchecked(offset);
        uint256 payloadLength;
        (payloadLength, offset) = encoded.asUint16Unchecked(offset);
        (managerMessage.payload, offset) = encoded.sliceUnchecked(offset, payloadLength);
        encoded.checkLength(offset);
    }

    /// @dev Native Token Transfer payload.
    ///      The wire format is as follows:
    ///      - NTT_PREFIX - 4 bytes
    ///      - amount - 8 bytes
    ///      - sourceToken - 32 bytes
    ///      - to - 32 bytes
    ///      - toChain - 2 bytes
    struct NativeTokenTransfer {
        /// @notice Amount being transferred (big-endian uint256)
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
        return abi.encodePacked(NTT_PREFIX, m.amount, m.sourceToken, m.to, m.toChain);
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
        uint64 amount;
        (amount, offset) = encoded.asUint64Unchecked(offset);
        nativeTokenTransfer.amount = NormalizedAmount.wrap(amount);
        (nativeTokenTransfer.sourceToken, offset) = encoded.asBytes32Unchecked(offset);
        (nativeTokenTransfer.to, offset) = encoded.asBytes32Unchecked(offset);
        (nativeTokenTransfer.toChain, offset) = encoded.asUint16Unchecked(offset);
        encoded.checkLength(offset);
    }

    struct EndpointMessage {
        /// @notice
        bytes4 prefix;
        /// @notice Payload provided to the Endpoint contract by the Manager contract.
        bytes managerPayload;
    }

    /*
     * @dev Encodes an Endpoint message for communication between the Manager and the Endpoint.
     *
     * @param m The EndpointMessage struct containing the message details.
     * @return encoded The byte array corresponding to the encoded message.
     * @throws PayloadTooLong if the length of endpointId, managerPayload, or endpointPayload exceeds the allowed maximum.
     */
    function encodeEndpointMessage(EndpointMessage memory m)
        public
        pure
        returns (bytes memory encoded)
    {
        if (m.managerPayload.length > type(uint16).max) {
            revert PayloadTooLong(m.managerPayload.length);
        }

        uint16 managerPayloadLength = uint16(m.managerPayload.length);
        return abi.encodePacked(m.prefix, managerPayloadLength, m.managerPayload);
    }
}

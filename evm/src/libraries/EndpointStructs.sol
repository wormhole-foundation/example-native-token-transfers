// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

library EndpointStructs {
    using BytesParsing for bytes;

    error PayloadTooLong(uint256 size);

    /// @dev The wire format is as follows:
    ///     - chainId - 2 bytes
    ///     - sequence - 8 bytes
    ///     - msgType - 1 byte
    ///     - payloadLength - 2 bytes
    ///     - payload - `payloadLength` bytes
    struct EndpointManagerMessage {
        /// @notice chainId that message originates from
        uint16 chainId;
        /// @notice unique sequence number
        uint64 sequence;
        /// @notice type of the message, which determines how the payload should be decoded.
        uint8 msgType;
        /// @notice payload that corresponds to the type.
        bytes payload;
    }

    function endpointManagerMessageDigest(EndpointManagerMessage memory m)
        public
        pure
        returns (bytes32)
    {
        return keccak256(encodeEndpointManagerMessage(m));
    }

    function encodeEndpointManagerMessage(EndpointManagerMessage memory m)
        public
        pure
        returns (bytes memory encoded)
    {
        if (m.payload.length > type(uint16).max) {
            revert PayloadTooLong(m.payload.length);
        }
        uint16 payloadLength = uint16(m.payload.length);
        return abi.encodePacked(m.chainId, m.sequence, m.msgType, payloadLength, m.payload);
    }

    /*
     * @dev Parse a EndpointManagerMessage.
     *
     * @params encoded The byte array corresponding to the encoded message
     */
    function parseEndpointManagerMessage(bytes memory encoded)
        public
        pure
        returns (EndpointManagerMessage memory managerMessage)
    {
        uint256 offset = 0;
        (managerMessage.chainId, offset) = encoded.asUint16Unchecked(offset);
        (managerMessage.sequence, offset) = encoded.asUint64Unchecked(offset);
        (managerMessage.msgType, offset) = encoded.asUint8Unchecked(offset);
        uint256 payloadLength;
        (payloadLength, offset) = encoded.asUint16Unchecked(offset);
        (managerMessage.payload, offset) = encoded.sliceUnchecked(offset, payloadLength);
        encoded.checkLength(offset);
    }

    /// Token Transfer payload corresponding to type == 1
    /// @dev The wire format is as follows:
    ///    - amount - 32 bytes
    ///    - toLength - 2 bytes
    ///    - to - `toLength` bytes
    ///    - toChain - 2 bytes
    struct NativeTokenTransfer {
        /// @notice Amount being transferred (big-endian uint256)
        uint256 amount;
        /// @notice Address of the recipient.
        bytes to;
        /// @notice Chain ID of the recipient
        uint16 toChain;
    }

    function encodeNativeTokenTransfer(NativeTokenTransfer memory m)
        public
        pure
        returns (bytes memory encoded)
    {
        if (m.to.length > type(uint16).max) {
            revert PayloadTooLong(m.to.length);
        }
        uint16 toLength = uint16(m.to.length);
        return abi.encodePacked(m.amount, toLength, m.to, m.toChain);
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
        (nativeTokenTransfer.amount, offset) = encoded.asUint256Unchecked(offset);
        uint16 toLength;
        (toLength, offset) = encoded.asUint16Unchecked(offset);
        (nativeTokenTransfer.to, offset) = encoded.sliceUnchecked(offset, toLength);
        (nativeTokenTransfer.toChain, offset) = encoded.asUint16Unchecked(offset);
        encoded.checkLength(offset);
    }

    struct EndpointMessage {
        /// @notice Magic string (constant value set by messaging provider) that idenfies the payload as an endpoint-emitted payload.
        ///         Note that this is not a security critical field. It's meant to be used by messaging providers to identify which messages are Endpoint-related.
        bytes32 endpointId;
        /// @notice Payload provided to the Endpoint contract by the EndpointManager contract.
        bytes managerPayload;
        /// @notice Custom payload which messaging providers can use to pass bridge-specific information, if needed.
        bytes endpointPayload;
    }
}

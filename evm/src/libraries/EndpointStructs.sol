// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

library EndpointStructs {
    using BytesParsing for bytes;

    error PayloadTooLong(uint256 size);

    /// @dev The wire format is as follows:
    ///     - chainId - 2 bytes
    ///     - sequence - 8 bytes
    ///     - sourceManagerLength - 2 bytes
    ///     - sourceManager - `sourceManagerLength` bytes
    ///     - senderLength - 2 bytes
    ///     - sender - `senderLength` bytes
    ///     - payloadLength - 2 bytes
    ///     - payload - `payloadLength` bytes
    struct ManagerMessage {
        /// @notice chainId that message originates from
        uint16 chainId;
        /// @notice unique sequence number
        uint64 sequence;
        /// @notice manager contract address that this message originates from.
        bytes sourceManager;
        /// @notice original message sender address.
        bytes sender;
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
        if (m.sourceManager.length > type(uint16).max) {
            revert PayloadTooLong(m.sourceManager.length);
        }
        uint16 sourceManagerLength = uint16(m.sourceManager.length);
        if (m.sender.length > type(uint16).max) {
            revert PayloadTooLong(m.sender.length);
        }
        uint16 senderLength = uint16(m.sender.length);
        if (m.payload.length > type(uint16).max) {
            revert PayloadTooLong(m.payload.length);
        }
        uint16 payloadLength = uint16(m.payload.length);
        return abi.encodePacked(
            m.chainId,
            m.sequence,
            sourceManagerLength,
            m.sourceManager,
            senderLength,
            m.sender,
            payloadLength,
            m.payload
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
        uint256 sourceManagerLength;
        (sourceManagerLength, offset) = encoded.asUint16Unchecked(offset);
        (managerMessage.sourceManager, offset) = encoded.sliceUnchecked(offset, sourceManagerLength);
        uint256 senderLength;
        (senderLength, offset) = encoded.asUint16Unchecked(offset);
        (managerMessage.sender, offset) = encoded.sliceUnchecked(offset, senderLength);
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
        /// @notice Payload provided to the Endpoint contract by the Manager contract.
        bytes managerPayload;
        /// @notice Custom payload which messaging providers can use to pass bridge-specific information, if needed.
        bytes endpointPayload;
    }
}

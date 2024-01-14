// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

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

struct EndpointMessage {
    /// @notice Magic string (constant value set by messaging provider) that idenfies the payload as an endpoint-emitted payload.
    ///         Note that this is not a security critical field. It's meant to be used by messaging providers to identify which messages are Endpoint-related.
    bytes32 endpointId;
    /// @notice Payload provided to the Endpoint contract by the EndpointManager contract.
    bytes managerPayload;
    /// @notice Custom payload which messaging providers can use to pass bridge-specific information, if needed.
    bytes endpointPayload;
}

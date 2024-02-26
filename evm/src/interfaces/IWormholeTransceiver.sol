// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TransceiverStructs.sol";

import "./IWormholeTransceiverState.sol";

interface IWormholeTransceiver is IWormholeTransceiverState {
    struct WormholeTransceiverInstruction {
        bool shouldSkipRelayerSend;
    }

    event ReceivedRelayedMessage(bytes32 digest, uint16 emitterChainId, bytes32 emitterAddress);
    event ReceivedMessage(
        bytes32 digest, uint16 emitterChainId, bytes32 emitterAddress, uint64 sequence
    );
    event SendTransceiverMessage(
        uint16 recipientChain, TransceiverStructs.TransceiverMessage message
    );

    error InvalidRelayingConfig(uint16 chainId);
    error InvalidWormholePeer(uint16 chainId, bytes32 peerAddress);
    error TransferAlreadyCompleted(bytes32 vaaHash);

    /// @notice Receive an attested message from the verification layer. This function should verify
    /// the `encodedVm` and then deliver the attestation to the transceiver NttManager contract.
    /// @param encodedMessage The attested message.
    function receiveMessage(bytes memory encodedMessage) external;

    /// @notice Parses the encoded instruction and returns the instruction struct. This instruction
    /// is specific to the WormholeTransceiver contract.
    /// @param encoded The encoded instruction.
    /// @return instruction The parsed `WormholeTransceiverInstruction`.
    function parseWormholeTransceiverInstruction(bytes memory encoded)
        external
        pure
        returns (WormholeTransceiverInstruction memory instruction);

    /// @notice Encodes the `WormholeTransceiverInstruction` into a byte array.
    /// @param instruction The `WormholeTransceiverInstruction` to encode.
    /// @return encoded The encoded instruction.
    function encodeWormholeTransceiverInstruction(WormholeTransceiverInstruction memory instruction)
        external
        pure
        returns (bytes memory);
}

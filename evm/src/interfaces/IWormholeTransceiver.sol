// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TransceiverStructs.sol";

interface IWormholeTransceiver {
    event ReceivedRelayedMessage(bytes32 digest, uint16 emitterChainId, bytes32 emitterAddress);
    event ReceivedMessage(
        bytes32 digest, uint16 emitterChainId, bytes32 emitterAddress, uint64 sequence
    );

    event SendTransceiverMessage(
        uint16 recipientChain, TransceiverStructs.TransceiverMessage message
    );
    event RelayingInfo(uint8 relayingType, uint256 deliveryPayment);
    event SetWormholePeer(uint16 chainId, bytes32 peerContract);
    event SetIsWormholeRelayingEnabled(uint16 chainId, bool isRelayingEnabled);
    event SetIsSpecialRelayingEnabled(uint16 chainId, bool isRelayingEnabled);
    event SetIsWormholeEvmChain(uint16 chainId);

    error InvalidRelayingConfig(uint16 chainId);
    error CallerNotRelayer(address caller);
    error UnexpectedAdditionalMessages();
    error InvalidVaa(string reason);
    error InvalidWormholePeer(uint16 chainId, bytes32 peerAddress);
    error PeerAlreadySet(uint16 chainId, bytes32 peerAddress);
    error TransferAlreadyCompleted(bytes32 vaaHash);
    error InvalidWormholePeerZeroAddress();
    error InvalidWormholeChainIdZero();

    function receiveMessage(bytes memory encodedMessage) external;
    function isVAAConsumed(bytes32 hash) external view returns (bool);
    function getWormholePeer(uint16 chainId) external view returns (bytes32);
    function isWormholeRelayingEnabled(uint16 chainId) external view returns (bool);
    function isSpecialRelayingEnabled(uint16 chainId) external view returns (bool);
    function isWormholeEvmChain(uint16 chainId) external view returns (bool);
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "../libraries/EndpointStructs.sol";

interface IWormholeEndpoint {
    event ReceivedRelayedMessage(bytes32 digest, uint16 emitterChainId, bytes32 emitterAddress);
    event ReceivedMessage(
        bytes32 digest, uint16 emitterChainId, bytes32 emitterAddress, uint64 sequence
    );

    event SendEndpointMessage(uint16 recipientChain, EndpointStructs.EndpointMessage message);
    event SetWormholeSibling(uint16 chainId, bytes32 oldSiblingContract, bytes32 siblingContract);

    error CallerNotRelayer(address caller);
    error RelayingNotImplemented(uint16 recipientChain);
    error UnexpectedAdditionalMessages();
    error InvalidVaa(string reason);
    error InvalidWormholeSibling(uint16 chainId, bytes32 siblingAddress);
    error TransferAlreadyCompleted(bytes32 vaaHash);
    error InvalidWormholeSiblingZeroAddress();
    error InvalidWormholeChainIdZero();

    function isVAAConsumed(bytes32 hash) external view returns (bool);
    function getWormholeSibling(uint16 chainId) external view returns (bytes32);
    function isWormholeRelayingEnabled(uint16 chainId) external view returns (bool);
    function isWormholeEvmChain(uint16 chainId) external view returns (bool);
}

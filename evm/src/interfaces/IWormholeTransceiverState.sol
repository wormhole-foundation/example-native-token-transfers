// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TransceiverStructs.sol";

interface IWormholeTransceiverState {
    event RelayingInfo(uint8 relayingType, uint256 deliveryPayment);
    event SetWormholePeer(uint16 chainId, bytes32 peerContract);
    event SetIsWormholeRelayingEnabled(uint16 chainId, bool isRelayingEnabled);
    event SetIsSpecialRelayingEnabled(uint16 chainId, bool isRelayingEnabled);
    event SetIsWormholeEvmChain(uint16 chainId);

    error UnexpectedAdditionalMessages();
    error InvalidVaa(string reason);
    error PeerAlreadySet(uint16 chainId, bytes32 peerAddress);
    error InvalidWormholePeerZeroAddress();
    error InvalidWormholeChainIdZero();
    error CallerNotRelayer(address caller);

    /// @notice Get the corresponding Transceiver contract on other chains that have been registered
    /// via governance. This design should be extendable to other chains, so each Transceiver would
    /// be potentially concerned with Transceivers on multiple other chains.
    /// @dev that peers are registered under Wormhole chain ID values.
    /// @param chainId The Wormhole chain ID of the peer to get.
    /// @return peerContract The address of the peer contract on the given chain.
    function getWormholePeer(uint16 chainId) external view returns (bytes32);

    /// @notice Returns a boolean indicating whether the given VAA hash has been consumed.
    /// @param hash The VAA hash to check.
    function isVAAConsumed(bytes32 hash) external view returns (bool);

    /// @notice Returns a boolean indicating whether Wormhole relaying is enabled for the given chain.
    /// @param chainId The Wormhole chain ID to check.
    function isWormholeRelayingEnabled(uint16 chainId) external view returns (bool);

    /// @notice Returns a boolean indicating whether special relaying is enabled for the given chain.
    /// @param chainId The Wormhole chain ID to check.
    function isSpecialRelayingEnabled(uint16 chainId) external view returns (bool);

    /// @notice Returns a boolean indicating whether the given chain is EVM compatible.
    /// @param chainId The Wormhole chain ID to check.
    function isWormholeEvmChain(uint16 chainId) external view returns (bool);

    /// @notice Set the Wormhole peer contract for the given chain.
    /// @dev This function is only callable by the `owner`.
    /// @param chainId The Wormhole chain ID of the peer to set.
    /// @param peerContract The address of the peer contract on the given chain.
    function setWormholePeer(uint16 chainId, bytes32 peerContract) external;

    /// @notice Set whether the chain is EVM compatible.
    /// @dev This function is only callable by the `owner`.
    /// @param chainId The Wormhole chain ID to set.
    function setIsWormholeEvmChain(uint16 chainId) external;

    /// @notice Set whether Wormhole relaying is enabled for the given chain.
    /// @dev This function is only callable by the `owner`.
    /// @param chainId The Wormhole chain ID to set.
    /// @param isRelayingEnabled A boolean indicating whether relaying is enabled.
    function setIsWormholeRelayingEnabled(uint16 chainId, bool isRelayingEnabled) external;
}

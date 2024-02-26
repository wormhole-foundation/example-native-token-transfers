// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TrimmedAmount.sol";
import "../libraries/TransceiverStructs.sol";

import "./INttManagerState.sol";

interface INttManagerState {
    /// @notice The caller is not the deployer.
    error UnexpectedDeployer(address expectedOwner, address owner);

    /// @notice Peer for the chain does not match the configuration.
    /// @param chainId ChainId of the source chain.
    /// @param peerAddress Address of the peer nttManager contract.
    error InvalidPeer(uint16 chainId, bytes32 peerAddress);

    /// @notice Peer chain ID cannot be zero.
    error InvalidPeerChainIdZero();

    /// @notice Peer cannot be the zero address.
    error InvalidPeerZeroAddress();

    /// @notice The number of thresholds should not be zero.
    error ZeroThreshold();

    /// @notice The threshold for transceiver attestations is too high.
    /// @param threshold The threshold.
    /// @param transceivers The number of transceivers.
    error ThresholdTooHigh(uint256 threshold, uint256 transceivers);
    error RetrievedIncorrectRegisteredTransceivers(uint256 retrieved, uint256 registered);

    /// @notice Sets the transceiver for the given chain.
    /// @param transceiver The address of the transceiver.
    /// @dev This method can only be executed by the `owner`.
    function setTransceiver(address transceiver) external;

    /// @notice Removes the transceiver for the given chain.
    /// @param transceiver The address of the transceiver.
    /// @dev This method can only be executed by the `owner`.
    function removeTransceiver(address transceiver) external;

    /// @notice Sets the threshold for the number of attestations required for a message
    /// to be considered valid.
    /// @param threshold The new threshold.
    /// @dev This method can only be executed by the `owner`.
    function setThreshold(uint8 threshold) external;

    /// @notice Returns registered peer contract for a given chain.
    /// @param chainId_ chain ID.
    function getPeer(uint16 chainId_) external view returns (bytes32);

    /// @notice Sets the corresponding peer.
    /// @dev The nttManager that executes the message sets the source nttManager as the peer.
    /// @param peerChainId The chain ID of the peer.
    /// @param peerContract The address of the peer nttManager contract.
    function setPeer(uint16 peerChainId, bytes32 peerContract) external;

    /// @notice Checks if a message has been approved. The message should have at least
    /// the minimum threshold of attestations from distinct endpoints.
    /// @param digest The digest of the message.
    /// @return - Boolean indicating if message has been approved.
    function isMessageApproved(bytes32 digest) external view returns (bool);

    /// @notice Checks if a message has been executed.
    /// @param digest The digest of the message.
    /// @return - Boolean indicating if message has been executed.
    function isMessageExecuted(bytes32 digest) external view returns (bool);

    /// @notice Sets the outbound transfer limit for a given chain.
    /// @dev This method can only be executed by the `owner`.
    /// @param limit The new outbound limit.
    function setOutboundLimit(uint256 limit) external;

    /// @notice Sets the inbound transfer limit for a given chain.
    /// @dev This method can only be executed by the `owner`.
    /// @param limit The new limit.
    /// @param chainId The chain to set the limit for.
    function setInboundLimit(uint256 limit, uint16 chainId) external;

    /// @notice Returns the next message sequence.
    function nextMessageSequence() external view returns (uint64);

    /// @notice Upgrades to a new manager implementation.
    /// @dev This is upgraded via a proxy, and can only be executed
    /// by the `owner`.
    /// @param newImplementation The address of the new implementation.
    function upgrade(address newImplementation) external;

    /// @notice Pauses the manager.
    function pause() external;

    /// @notice Returns the mode (locking or burning) of the NttManager.
    /// @return mode A uint8 corresponding to the mode
    function getMode() external view returns (uint8);

    /// @notice Returns the number of Transceivers that must attest to a msgId for
    /// it to be considered valid and acted upon.
    function getThreshold() external view returns (uint8);

    /// @notice Returns a boolean indicating if the transceiver has attested to the message.
    function transceiverAttestedToMessage(
        bytes32 digest,
        uint8 index
    ) external view returns (bool);

    /// @notice Returns the number of attestations for a given message.
    function messageAttestations(bytes32 digest) external view returns (uint8 count);

    /// @notice Returns of the address of the token managed by this contract.
    function token() external view returns (address);

    /// @notice Returns the chain ID.
    function chainId() external view returns (uint16);
}

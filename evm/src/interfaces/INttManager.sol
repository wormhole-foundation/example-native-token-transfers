// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/NormalizedAmount.sol";
import "../libraries/TransceiverStructs.sol";

interface INttManager {
    /// @notice payment for a transfer is too low.
    /// @param requiredPayment The required payment.
    /// @param providedPayment The provided payment.
    error DeliveryPaymentTooLow(uint256 requiredPayment, uint256 providedPayment);

    /// @notice The transfer has some dust.
    /// @dev This is a security measure to prevent users from losing funds.
    /// This is the result of normalizing the amount and then denormalizing it.
    /// @param amount The amount to transfer.
    error TransferAmountHasDust(uint256 amount, uint256 dust);

    error MessageNotApproved(bytes32 msgHash);
    error InvalidTargetChain(uint16 targetChain, uint16 thisChain);
    error ZeroAmount();
    error InvalidRecipient();
    error BurnAmountDifferentThanBalanceDiff(uint256 burnAmount, uint256 balanceDiff);

    /// @notice The mode is invalid. It is neither in LOCKING or BURNING mode.
    /// @param mode The mode.
    error InvalidMode(uint8 mode);

    /// @notice the peer for the chain does not match the configuration.
    /// @param chainId ChainId of the source chain.
    /// @param peerAddress Address of the peer nttManager contract.
    error InvalidPeer(uint16 chainId, bytes32 peerAddress);
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

    /// @notice Transfer a given amount to a recipient on a given chain. This function is called
    /// by the user to send the token cross-chain. This function will either lock or burn the 
    /// sender's tokens. Finally, this function will call into registered `Endpoint` contracts
    /// to send a message with the incrementing sequence number and the token transfer payload.
    /// @param amount The amount to transfer.
    /// @param recipientChain The Wormhole chain ID for the destination.
    /// @param recipient The recipient address.
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) external payable returns (uint64 msgId); 

    /// @notice Transfer a given amount to a recipient on a given chain. This function is called
    /// by the user to send the token cross-chain. This function will either lock or burn the 
    /// sender's tokens. Finally, this function will call into registered `Endpoint` contracts
    /// to send a message with the incrementing sequence number and the token transfer payload.
    /// @dev Transfers are queued if the outbound limit is hit and must be completed by the client.
    /// @param amount The amount to transfer.
    /// @param recipientChain The Wormhole chain ID for the destination.
    /// @param recipient The recipient address.
    /// @param shouldQueue Whether the transfer should be queued if the outbound limit is hit.
    /// @param encodedInstructions Additional instructions to be forwarded to the recipient chain.
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bool shouldQueue,
        bytes memory encodedInstructions
    ) external payable returns (uint64 msgId);

    /// @notice Returns registered sibling contract for a given chain.
    /// @param chainId_ Wormhole chain ID. 
    function getSibling(uint16 chainId_) external view returns (bytes32);

    /// @notice Registers a sibling contract from on a different chain. 
    /// @dev The manager that executes the message sets the source manager as the sibling.
    /// This method can only be executed by the `owner`.
    /// @param siblingChainId Wormhole chain ID for the sibling chain.
    /// @param siblingContract Sibling contract address in Wormhole universal format.
    function setSibling(uint16 siblingChainId, bytes32 siblingContract) external;

    /// @notice deeznuts
    function setEndpoint(address endpoint) external;

    /// @notice deeznuts
    function removeEndpoint(address endpoint) external;

    /// @notice deeznuts
    function setThreshold(uint8 threshold) external;

    /// @notice Checks if a message has been approved. The message should have at least
    /// the minimum threshold of attestations fron distinct endpoints.
    /// @param digest The digest of the message.
    /// @return - Boolean indicating if message has been approved.
    function isMessageApproved(bytes32 digest) external view returns (bool);

    /// @notice Checks if a message has been executed.
    /// @param digest The digest of the message. 
    /// @return - Boolean indicating if message has been executed.
    function isMessageExecuted(bytes32 digest) external view returns (bool);

    /// @notice deeznuts
    function endpointAttestedToMessage(bytes32 digest, uint8 index) external view returns (bool);

    /// @dev Returns the number of attestations from enabled endpoints for a given message.
    /// @param digest Digest of the message.
    function messageAttestations(bytes32 digest) external view returns (uint8 count);

    /// @notice Complete an outbound trasnfer that's been queued.
    /// @dev This method is called by the client to complete an outbound transfer that's been queued.
    /// @param queueSequence The sequence of the message in the queue.
    /// @return msgSequence The sequence of the message.
    function completeOutboundQueuedTransfer(uint64 queueSequence)
        external
        payable
        returns (uint64 msgSequence);

    /// @notice Complete an inbound queued transfer.
    /// @param digest The digest of the message to complete.
    function completeInboundQueuedTransfer(bytes32 digest) external;

    /// @notice Set the outbound transfer limit for a given chain.
    /// @dev This method can only be executed by the `owner`.
    /// @param limit The new outbound limit.
    function setOutboundLimit(uint256 limit) external;

    /// @notice Set the inbound transfer limit for a given chain.
    /// @dev This method can only be executed by the `owner`.
    /// @param limit The new limit.
    /// @param chainId The chain to set the limit for.
    function setInboundLimit(uint256 limit, uint16 chainId) external;

    /// @notice Fetch the delivery price for a given recipient chain transfer.
    /// @param recipientChain The Wormhole chain ID of the transfer destination.
    /// @param endpointInstructions An additional instruction the endpoint can forward to the 
    /// recipient chain.
    /// @return The delivery prices associated with each endpoint.
    function quoteDeliveryPrice(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction[] memory transceiverInstructions,
        address[] memory enabledTransceivers
    ) external view returns (uint256[] memory, uint256);

    /// @notice Returns the next message sequence. 
    function nextMessageSequence() external view returns (uint64);

    /// @notice Returns of the address of the token managed by this contract. 
    function token() external view returns (address);

    /// @notice Returns the address that the deployed the manager implementation.
    function deployer() external view returns (address);

    /// @notice Returns the mode (BURNING or LOCKING). 
    function mode() external view returns (Mode);

    /// @notice Returns the Wormhole chain ID. 
    function chainId() external view returns (uint16);

    /// @notice Returns the EVM chain ID.
    function evmChainId() external view returns (uint256);

    /// @notice Returns the number of Endpoints that must attest to a msgId for it to be 
    /// considered valid and acted upon.
    function getThreshold() external view returns (uint8);

    /// @notice deeznuts
    function executeMsg(
        uint16 sourceChainId,
        bytes32 sourceManagerAddress,
        EndpointStructs.ManagerMessage memory message
    ) external;

    /// @notice Called by an Endpoint contract to deliver a verified attestation.
    /// @dev This function enforces attestation threshold and replay logic for messages. Once all
    /// validations are complete, this function calls `executeMsg` to execute the command specified
    /// by the message.
    /// @param sourceChainId The chain id of the sender.
    /// @param sourceNttManagerAddress The address of the sender's nttManager contract.
    /// @param payload The VAA payload.
    function attestationReceived(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory payload
    ) external;

    /// @notice upgrade to a new manager implementation.
    /// @dev This is upgraded via a proxy, and can only be executed 
    /// by the `owner`.
    /// @param newImplementation The address of the new implementation.
    function upgrade(address newImplementation) external;

    /// @notice Pauses the manager.
    function pause() external;
}

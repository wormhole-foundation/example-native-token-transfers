// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TrimmedAmount.sol";
import "../libraries/TransceiverStructs.sol";

interface INttManager {
    /// @notice payment for a transfer is too low.
    /// @param requiredPayment The required payment.
    /// @param providedPayment The provided payment.
    error DeliveryPaymentTooLow(uint256 requiredPayment, uint256 providedPayment);

    //// @notice The transfer has some dust.
    //// @dev    This is a security measure to prevent users from losing funds.
    ////         This is the result of trimming the amount and then untrimming it.
    //// @param  amount The amount to transfer.
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

    // @notice                       transfer a given amount to a recipient on a given chain.
    // @dev                          transfers are queued if the outbound limit is hit
    //                               and must be completed by the client.
    //
    // @param amount                 The amount to transfer.
    // @param recipientChain         The chain to transfer to.
    // @param recipient              The recipient address.
    // @param shouldQueue            Whether the transfer should be queued if the outbound limit is hit.
    // @param encodedInstructions    Additional instructions to be forwarded to the recipient chain.
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bool shouldQueue,
        bytes memory encodedInstructions
    ) external payable returns (uint64 msgId);

    function getPeer(uint16 chainId_) external view returns (bytes32);

    function setPeer(uint16 peerChainId, bytes32 peerContract) external;

    /// @notice Check if a message has been approved. The message should have at least
    /// the minimum threshold of attestations fron distinct transceivers.
    ///
    /// @param digest The digest of the message.
    /// @return Whether the message has been approved.
    function isMessageApproved(bytes32 digest) external view returns (bool);

    function isMessageExecuted(bytes32 digest) external view returns (bool);

    /// @notice Complete an outbound trasnfer that's been queued.
    /// @dev    This method is called by the client to complete an
    ///         outbound transfer that's been queued.
    ///
    /// @param queueSequence The sequence of the message in the queue.
    /// @return msgSequence The sequence of the message.
    function completeOutboundQueuedTransfer(uint64 queueSequence)
        external
        payable
        returns (uint64 msgSequence);

    // @notice      Complete an inbound queued transfer.
    // @param       digest The digest of the message to complete.
    function completeInboundQueuedTransfer(bytes32 digest) external;

    // @notice     Set the outbound transfer limit for a given chain.
    // @param      limit The new limit.
    function setOutboundLimit(uint256 limit) external;

    // @notice           Set the inbound transfer limit for a given chain.
    // @param limit      The new limit.
    // @param chainId    The chain to set the limit for.
    function setInboundLimit(uint256 limit, uint16 chainId) external;

    // @notice                         Fetch the delivery price for a given recipient chain transfer.
    // @param recipientChain           The chain to transfer to.
    // @param transceiverInstructions     An additional instruction the transceiver can forward to
    //                                 the recipient chain.
    // @param enabledTransceivers         The transceivers that are enabled for the transfer.
    // @return                         The delivery prices associated with each transceiver, and the sum
    //                                 of these prices.
    function quoteDeliveryPrice(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction[] memory transceiverInstructions,
        address[] memory enabledTransceivers
    ) external view returns (uint256[] memory, uint256);

    function nextMessageSequence() external view returns (uint64);

    function token() external view returns (address);

    /// @notice Called by an Transceiver contract to deliver a verified attestation.
    /// @dev    This function enforces attestation threshold and replay logic for messages.
    ///         Once all validations are complete, this function calls _executeMsg to execute
    ///         the command specified by the message.
    /// @param sourceChainId The chain id of the sender.
    /// @param sourceNttManagerAddress The address of the sender's nttManager contract.
    /// @param payload The VAA payload.
    function attestationReceived(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory payload
    ) external;

    /// @notice upgrade to a new nttManager implementation.
    /// @dev This is upgraded via a proxy.
    ///
    /// @param newImplementation The address of the new implementation.
    function upgrade(address newImplementation) external;

    /// @notice Returns the mode (locking or burning) of the NttManager.
    /// @return mode A uint8 corresponding to the mode
    function getMode() external view returns (uint8);

    /// @notice Returns the number of decimals of the token managed by the NttManager.
    /// @return decimals The number of decimals of the token.
    function tokenDecimals() external view returns (uint8);
}

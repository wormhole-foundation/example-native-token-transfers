// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/NormalizedAmount.sol";
import "../libraries/EndpointStructs.sol";

interface IManager {
    /// @notice payment for a transfer is too low.
    /// @param requiredPayment The required payment.
    /// @param providedPayment The provided payment.
    error DeliveryPaymentTooLow(uint256 requiredPayment, uint256 providedPayment);

    //// @notice The transfer has some dust.
    //// @dev    This is a security measure to prevent users from losing funds.
    ////         This is the result of normalizing the amount and then denormalizing it.
    //// @param  amount The amount to transfer.
    error TransferAmountHasDust(uint256 amount, uint256 dust);

    error MessageNotApproved(bytes32 msgHash);
    error InvalidTargetChain(uint16 targetChain, uint16 thisChain);
    error ZeroAmount();
    error BurnAmountDifferentThanBalanceDiff(uint256 burnAmount, uint256 balanceDiff);

    /// @notice The mode is invalid. It is neither in LOCKING or BURNING mode.
    /// @param mode The mode.
    error InvalidMode(uint8 mode);

    /// @notice the sibling for the chain does not match the configuration.
    /// @param chainId ChainId of the source chain.
    /// @param siblingAddress Address of the sibling manager contract.
    error InvalidSibling(uint16 chainId, bytes32 siblingAddress);
    error InvalidSiblingChainIdZero();

    /// @notice Sibling cannot be the zero address.
    error InvalidSiblingZeroAddress();

    /// @notice The number of thresholds should not be zero.
    error ZeroThreshold();

    /// @notice The threshold for endpoint attestations is too high.
    /// @param threshold The threshold.
    /// @param endpoints The number of endpoints.
    error ThresholdTooHigh(uint256 threshold, uint256 endpoints);
    error RetrievedIncorrectRegisteredEndpoints(uint256 retrieved, uint256 registered);

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

    function getSibling(uint16 chainId_) external view returns (bytes32);

    function setSibling(uint16 siblingChainId, bytes32 siblingContract) external;

    /// @notice Check if a message has been approved. The message should have at least
    /// the minimum threshold of attestations fron distinct endpoints.
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
    // @param endpointInstructions     An additional instruction the endpoint can forward to
    //                                 the recipient chain.
    // @return                         The delivery prices associated with each endpoint.
    function quoteDeliveryPrice(
        uint16 recipientChain,
        EndpointStructs.EndpointInstruction[] memory endpointInstructions
    ) external view returns (uint256[] memory);

    function nextMessageSequence() external view returns (uint64);

    function token() external view returns (address);

    /// @notice Called by an Endpoint contract to deliver a verified attestation.
    /// @dev    This function enforces attestation threshold and replay logic for messages.
    ///         Once all validations are complete, this function calls _executeMsg to execute
    ///         the command specified by the message.
    /// @param sourceChainId The chain id of the sender.
    /// @param sourceManagerAddress The address of the sender's manager contract.
    /// @param payload The VAA payload.
    function attestationReceived(
        uint16 sourceChainId,
        bytes32 sourceManagerAddress,
        EndpointStructs.ManagerMessage memory payload
    ) external;

    /// @notice upgrade to a new manager implementation.
    /// @dev This is upgraded via a proxy.
    ///
    /// @param newImplementation The address of the new implementation.
    function upgrade(address newImplementation) external;

    /// @notice Returns the mode (locking or burning) of the Manager.
    /// @return mode A uint8 corresponding to the mode
    function getMode() external view returns (uint8);

    /// @notice Returns the number of decimals of the token managed by the Manager.
    /// @return decimals The number of decimals of the token.
    function tokenDecimals() external view returns (uint8);
}

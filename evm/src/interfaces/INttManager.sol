// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TrimmedAmount.sol";
import "../libraries/TransceiverStructs.sol";

import "./INttManagerState.sol";

interface INttManager is INttManagerState {
    /// @notice The mode is either LOCKING or BURNING. In LOCKING mode, the NttManager locks the
    ///         tokens of the sender and mints an equivalent amount on the target chain. In BURNING
    ///         mode, the NttManager burns the tokens of the sender and mints an equivalent amount
    ///         on the target chain.LOCKING mode preserves the total supply of the tokens.
    enum Mode {
        LOCKING,
        BURNING
    }

    /// @notice Information about attestations for a given message.
    /// @dev The fields are as follows:
    ///      - executed: whether the message has been executed.
    ///      - attested: bitmap of transceivers that have attested to this message.
    ///                  (NOTE: might contain disabled transceivers)
    struct AttestationInfo {
        bool executed;
        uint64 attestedTransceivers;
    }

    struct _Sequence {
        uint64 num;
    }

    struct _Threshold {
        uint8 num;
    }

    /// @notice payment for a transfer is too low.
    /// @param requiredPayment The required payment.
    /// @param providedPayment The provided payment.
    error DeliveryPaymentTooLow(uint256 requiredPayment, uint256 providedPayment);

    //// @notice The transfer has some dust.
    //// @dev This is a security measure to prevent users from losing funds.
    ////      This is the result of trimming the amount and then untrimming it.
    //// @param  amount The amount to transfer.
    error TransferAmountHasDust(uint256 amount, uint256 dust);

    /// @notice The mode is invalid. It is neither in LOCKING or BURNING mode.
    /// @param mode The mode.
    error InvalidMode(uint8 mode);

    /// @notice Error when the refund to the sender fails.
    /// @dev Selector 0x2ca23714.
    /// @param refundAmount The refund amount.
    error RefundFailed(uint256 refundAmount);

    /// @notice Error when the tranceiver already attested to the message.
    ///         To ensure the client does not continue to initiate calls to the attestationReceived function.
    /// @dev Selector 0x2113894.
    /// @param nttManagerMessageHash The hash of the message.
    error TransceiverAlreadyAttestedToMessage(bytes32 nttManagerMessageHash);

    /// @notice Error when the message is not approved.
    /// @dev Selector 0x451c4fb0.
    /// @param msgHash The hash of the message.
    error MessageNotApproved(bytes32 msgHash);

    /// @notice Error when trying to execute a message on an unintended target chain.
    /// @dev Selector 0x3dcb204a.
    /// @param targetChain The target chain.
    /// @param thisChain The current chain.
    error InvalidTargetChain(uint16 targetChain, uint16 thisChain);

    /// @notice Error when the transfer amount is zero.
    /// @dev Selector 0x9993626a.
    error ZeroAmount();

    /// @notice Error when the recipient is invalid.
    /// @dev Selector 0x9c8d2cd2.
    error InvalidRecipient();

    /// @notice Error when the amount burned is different than the balance difference,
    ///         since NTT does not support burn fees.
    /// @dev Selector 0x02156a8f.
    /// @param burnAmount The amount burned.
    /// @param balanceDiff The balance after burning.
    error BurnAmountDifferentThanBalanceDiff(uint256 burnAmount, uint256 balanceDiff);

    /// @notice Transfer a given amount to a recipient on a given chain. This function is called
    ///         by the user to send the token cross-chain. This function will either lock or burn the
    ///         sender's tokens. Finally, this function will call into registered `Endpoint` contracts
    ///         to send a message with the incrementing sequence number and the token transfer payload.
    /// @param amount The amount to transfer.
    /// @param recipientChain The chain ID for the destination.
    /// @param recipient The recipient address.
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) external payable returns (uint64 msgId);

    /// @notice Transfer a given amount to a recipient on a given chain. This function is called
    ///         by the user to send the token cross-chain. This function will either lock or burn the
    ///         sender's tokens. Finally, this function will call into registered `Endpoint` contracts
    ///         to send a message with the incrementing sequence number and the token transfer payload.
    /// @dev Transfers are queued if the outbound limit is hit and must be completed by the client.
    /// @param amount The amount to transfer.
    /// @param recipientChain The chain ID for the destination.
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

    /// @notice Complete an outbound transfer that's been queued.
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

    /// @notice Fetch the delivery price for a given recipient chain transfer.
    /// @param recipientChain The chain ID of the transfer destination.
    /// @return - The delivery prices associated with each endpoint and the total price.
    function quoteDeliveryPrice(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction[] memory transceiverInstructions,
        address[] memory enabledTransceivers
    ) external view returns (uint256[] memory, uint256);

    /// @notice Called by an Endpoint contract to deliver a verified attestation.
    /// @dev This function enforces attestation threshold and replay logic for messages. Once all
    ///      validations are complete, this function calls `executeMsg` to execute the command specified
    ///      by the message.
    /// @param sourceChainId The chain id of the sender.
    /// @param sourceNttManagerAddress The address of the sender's nttManager contract.
    /// @param payload The VAA payload.
    function attestationReceived(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory payload
    ) external;

    /// @notice Called after a message has been sufficiently verified to execute
    ///         the command in the message. This function will decode the payload
    ///         as an NttManagerMessage to extract the sequence, msgType, and other parameters.
    /// @dev This function is exposed as a fallback for when an `Transceiver` is deregistered
    ///      when a message is in flight.
    /// @param sourceChainId The chain id of the sender.
    /// @param sourceNttManagerAddress The address of the sender's nttManager contract.
    /// @param message The message to execute.
    function executeMsg(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory message
    ) external;

    /// @notice Returns the number of decimals of the token managed by the NttManager.
    /// @return decimals The number of decimals of the token.
    function tokenDecimals() external view returns (uint8);
}

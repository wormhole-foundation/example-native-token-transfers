// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TransceiverStructs.sol";

interface ITransceiver {
    /// @notice The caller is not the deployer.
    error UnexpectedDeployer(address deployer, address caller);
    error CallerNotNttManager(address caller);
    error CannotRenounceTransceiverOwnership(address currentOwner);
    error CannotTransferTransceiverOwnership(address currentOwner, address newOwner);
    error UnexpectedRecipientNttManagerAddress(
        bytes32 recipientNttManagerAddress, bytes32 expectedRecipientNttManagerAddress
    );

    /// @notice Fetch the delivery price for a given recipient chain transfer.
    /// @param recipientChain The Wormhole chain ID of the target chain.
    /// @param instruction An additional Instruction provided by the Transceiver to be
    /// executed on the recipient chain.
    /// @return deliveryPrice The cost of delivering a message to the recipient chain,
    /// in this chain's native token.
    function quoteDeliveryPrice(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction memory instruction
    ) external view returns (uint256);

    /// @dev Send a message to another chain.
    /// @param recipientChain The Wormhole chain ID of the recipient.
    /// @param instruction An additional Instruction provided by the Transceiver to be
    /// executed on the recipient chain.
    /// @param nttManagerMessage A message to be sent to the nttManager on the recipient chain.
    function sendMessage(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction memory instruction,
        bytes memory nttManagerMessage,
        bytes32 recipientNttManagerAddress
    ) external payable;

    /// @notice Upgrades the transceiver to a new implementation.
    function upgrade(address newImplementation) external;

    /// @notice Transfers the ownership of the transceiver to a new address.
    function transferTransceiverOwnership(address newOwner) external;
}

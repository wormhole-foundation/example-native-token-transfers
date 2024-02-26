// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TrimmedAmount.sol";

interface INttManagerEvents {
    /// @notice Emitted when a message is sent from the nttManager.
    /// @dev Topic0
    ///      0x9716fe52fe4e02cf924ae28f19f5748ef59877c6496041b986fbad3dae6a8ecf
    /// @param recipient The recipient of the message.
    /// @param amount The amount transferred.
    /// @param fee The amount of ether sent along with the tx to cover the delivery fee.
    /// @param recipientChain The chain ID of the recipient.
    /// @param msgSequence The unique sequence ID of the message.
    event TransferSent(
        bytes32 recipient, uint256 amount, uint256 fee, uint16 recipientChain, uint64 msgSequence
    );

    /// @notice Emitted when the peer contract is updated.
    /// @dev Topic0
    ///      0x1456404e7f41f35c3daac941bb50bad417a66275c3040061b4287d787719599d.
    /// @param chainId_ The chain ID of the peer contract.
    /// @param oldPeerContract The old peer contract address.
    /// @param oldPeerDecimals The old peer contract decimals.
    /// @param peerContract The new peer contract address.
    /// @param peerDecimals The new peer contract decimals.
    event PeerUpdated(
        uint16 indexed chainId_,
        bytes32 oldPeerContract,
        uint8 oldPeerDecimals,
        bytes32 peerContract,
        uint8 peerDecimals
    );

    /// @notice Emitted when a message has been attested to.
    /// @dev Topic0
    ///      0x35a2101eaac94b493e0dfca061f9a7f087913fde8678e7cde0aca9897edba0e5.
    /// @param digest The digest of the message.
    /// @param transceiver The address of the transceiver.
    /// @param index The index of the transceiver in the bitmap.
    event MessageAttestedTo(bytes32 digest, address transceiver, uint8 index);

    /// @notice Emmitted when the threshold required transceivers is changed.
    /// @dev Topic0
    ///      0x2a855b929b9a53c6fb5b5ed248b27e502b709c088e036a5aa17620c8fc5085a9.
    /// @param oldThreshold The old threshold.
    /// @param threshold The new threshold.
    event ThresholdChanged(uint8 oldThreshold, uint8 threshold);

    /// @notice Emitted when an transceiver is removed from the nttManager.
    /// @dev Topic0
    ///      0xc6289e62021fd0421276d06677862d6b328d9764cdd4490ca5ac78b173f25883.
    /// @param transceiver The address of the transceiver.
    /// @param transceiversNum The current number of transceivers.
    /// @param threshold The current threshold of transceivers.
    event TransceiverAdded(address transceiver, uint256 transceiversNum, uint8 threshold);

    /// @notice Emitted when an transceiver is removed from the nttManager.
    /// @dev Topic0
    ///     0x638e631f34d9501a3ff0295873b29f50d0207b5400bf0e48b9b34719e6b1a39e.
    /// @param transceiver The address of the transceiver.
    /// @param threshold The current threshold of transceivers.
    event TransceiverRemoved(address transceiver, uint8 threshold);

    /// @notice Emitted when a message has already been executed to
    ///         notify client of against retries.
    /// @dev Topic0
    ///      0x4069dff8c9df7e38d2867c0910bd96fd61787695e5380281148c04932d02bef2.
    /// @param sourceNttManager The address of the source nttManager.
    /// @param msgHash The keccak-256 hash of the message.
    event MessageAlreadyExecuted(bytes32 indexed sourceNttManager, bytes32 indexed msgHash);

    /// @notice Emitted when a transfer has been redeemed
    ///         (either minted or unlocked on the recipient chain).
    /// @dev Topic0
    ///      0x504e6efe18ab9eed10dc6501a417f5b12a2f7f2b1593aed9b89f9bce3cf29a91.
    /// @param digest The digest of the message.
    event TransferRedeemed(bytes32 indexed digest);
}

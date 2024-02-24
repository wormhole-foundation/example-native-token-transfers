// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/NormalizedAmount.sol";

interface IManagerEvents {

    /// @notice Emitted when a message is sent from the manager.
    /// @dev Topic0
    ///      0x71ec1d4b53baa86365b6523ea136c9fe0f72c36c721e7e28e9efac2c23b39d98.
    /// @param recipient The recipient of the message.
    /// @param amount The amount transferred.
    /// @param recipientChain The chain ID of the recipient.
    /// @param msgSequence The unique sequence ID of the message.
    event TransferSent(
        bytes32 recipient, uint256 amount, uint16 recipientChain, uint64 msgSequence
    );

    /// @notice Emitted when the sibling contract is updated.
    /// @dev Topic0
    ///      0x51b8437a7e22240c473f4cbdb4ed3a4f4bf5a9e7b3c511d7cfe0197325735700.
    /// @param chainId_ The chain ID of the sibling contract.
    /// @param oldSiblingContract The old sibling contract address.
    /// @param siblingContract The new sibling contract address.
    event SiblingUpdated(
        uint16 indexed chainId_, bytes32 oldSiblingContract, bytes32 siblingContract
    );

    /// @notice Emitted when a message has been attested to.
    /// @dev Topic0
    ///      0x35a2101eaac94b493e0dfca061f9a7f087913fde8678e7cde0aca9897edba0e5.
    /// @param digest The digest of the message.
    /// @param endpoint The address of the endpoint.
    /// @param index The index of the endpoint in the bitmap.
    event MessageAttestedTo(bytes32 digest, address endpoint, uint8 index);

    /// @notice Emmitted when the threshold required endpoints is changed.
    /// @dev Topic0
    ///      0x2a855b929b9a53c6fb5b5ed248b27e502b709c088e036a5aa17620c8fc5085a9.
    /// @param oldThreshold The old threshold.
    /// @param threshold The new threshold.
    event ThresholdChanged(uint8 oldThreshold, uint8 threshold);

    /// @notice Emitted when an endpoint is removed from the manager.
    /// @dev Topic0
    ///      0xc6289e62021fd0421276d06677862d6b328d9764cdd4490ca5ac78b173f25883.
    /// @param endpoint The address of the endpoint.
    /// @param endpointsNum The current number of endpoints.
    /// @param threshold The current threshold of endpoints.
    event EndpointAdded(address endpoint, uint256 endpointsNum, uint8 threshold);

    /// @notice Emitted when an endpoint is removed from the manager.
    /// @dev Topic0
    ///     0x638e631f34d9501a3ff0295873b29f50d0207b5400bf0e48b9b34719e6b1a39e.
    /// @param endpoint The address of the endpoint.
    /// @param threshold The current threshold of endpoints.
    event EndpointRemoved(address endpoint, uint8 threshold);

    /// @notice Emitted when a message has already been executed to
    ///         notify client of against retries.
    /// @dev Topic0
    ///      0x4069dff8c9df7e38d2867c0910bd96fd61787695e5380281148c04932d02bef2.
    /// @param sourceManager The address of the source manager.
    /// @param msgHash The keccak-256 hash of the message.
    event MessageAlreadyExecuted(bytes32 indexed sourceManager, bytes32 indexed msgHash);

    /// @notice Emitted when a transfer has been redeemed
    ///         (either minted or unlocked on the recipient chain).
    /// @dev Topic0
    ///      0x504e6efe18ab9eed10dc6501a417f5b12a2f7f2b1593aed9b89f9bce3cf29a91.
    /// @param digest The digest of the message.
    event TransferRedeemed(bytes32 digest);
}

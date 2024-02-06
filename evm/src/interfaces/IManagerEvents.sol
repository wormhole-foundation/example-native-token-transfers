// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.0 <0.9.0;

interface IManagerEvents {
    event TransferSent(
        bytes32 recipient,
        uint256 amount,
        uint256 normalizedAmount,
        uint16 recipientChain,
        uint64 msgSequence
    );
    event SiblingUpdated(uint16 indexed chainId_, bytes oldSiblingContract, bytes siblingContract);
    event MessageAttestedTo(bytes32 digest, address endpoint, uint8 index);
    event ThresholdChanged(uint8 oldThreshold, uint8 threshold);
    event EndpointAdded(address endpoint, uint8 threshold);
    event EndpointRemoved(address endpoint, uint8 threshold);
}

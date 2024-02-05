// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

interface IManagerEvents {
    event InboundTransferQueued(bytes32 digest);
    event OutboundTransferQueued(uint64 queueSequence);
    event TransferSent(
        bytes32 recipient,
        uint256 amount,
        uint256 normalizedAmount,
        uint16 recipientChain,
        uint64 msgSequence
    );
    event OutboundTransferRateLimited(
        address indexed sender, uint256 amount, uint256 currentCapacity
    );
    event SiblingUpdated(uint16 indexed chainId_, bytes oldSiblingContract, bytes siblingContract);
    event MessageAttestedTo(bytes32 digest, address endpoint, uint8 index);
    event ThresholdChanged(uint8 oldThreshold, uint8 threshold);
    event EndpointAdded(address endpoint, uint8 threshold);
    event EndpointRemoved(address endpoint, uint8 threshold);
}

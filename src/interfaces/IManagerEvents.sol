// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/NormalizedAmount.sol";

interface IManagerEvents {
    event TransferSent(
        bytes32 recipient, uint256 amount, uint16 recipientChain, uint64 msgSequence
    );
    event SiblingUpdated(
        uint16 indexed chainId_, bytes32 oldSiblingContract, bytes32 siblingContract
    );
    event MessageAttestedTo(bytes32 digest, address endpoint, uint8 index);
    event ThresholdChanged(uint8 oldThreshold, uint8 threshold);
    event EndpointAdded(address endpoint, uint8 threshold);
    event EndpointRemoved(address endpoint, uint8 threshold);
    event MessageAlreadyExecuted(bytes32 indexed sourceManager, bytes32 indexed msgHash);
}

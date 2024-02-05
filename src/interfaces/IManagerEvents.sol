// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

interface IManagerEvents {
    event InboundTransferQueued(bytes32 digest);
    event OutboundTransferQueued(uint64 queueSequence);
    event TransferSent(bytes32 recipient, uint16 recipientChain, uint64 msgSequence);
}

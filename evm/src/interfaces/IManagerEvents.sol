// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

interface IManagerEvents {
    event InboundTransferQueued(uint64 queueSequence, uint16 sourceChain);
}

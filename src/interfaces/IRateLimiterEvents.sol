// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.0 <0.9.0;

interface IRateLimiterEvents {
    event InboundTransferQueued(bytes32 digest);
    event OutboundTransferQueued(uint64 queueSequence);
    event OutboundTransferRateLimited(
        address indexed sender, uint64 sequence, uint256 amount, uint256 currentCapacity
    );
}

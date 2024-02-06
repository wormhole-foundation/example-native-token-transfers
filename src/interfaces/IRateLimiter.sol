// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.0 <0.9.0;

interface IRateLimiter {
    error NotEnoughCapacity(uint256 currentCapacity, uint256 amount);
    error OutboundQueuedTransferNotFound(uint64 queueSequence);
    error OutboundQueuedTransferStillQueued(uint64 queueSequence, uint256 transferTimestamp);
    error InboundQueuedTransferNotFound(bytes32 digest);
    error InboundQueuedTransferStillQueued(bytes32 digest, uint256 transferTimestamp);

    struct RateLimitParams {
        uint256 limit;
        uint256 currentCapacity;
        uint64 lastTxTimestamp;
    }

    struct OutboundQueuedTransfer {
        uint256 amount;
        bytes32 recipient;
        uint64 txTimestamp;
        uint16 recipientChain;
    }

    struct InboundQueuedTransfer {
        uint256 amount;
        uint64 txTimestamp;
        address recipient;
    }

    function getOutboundLimitParams() external view returns (RateLimitParams memory);

    function getCurrentOutboundCapacity() external view returns (uint256);

    function getOutboundQueuedTransfer(uint64 queueSequence)
        external
        view
        returns (OutboundQueuedTransfer memory);

    function getInboundLimitParams(uint16 chainId) external view returns (RateLimitParams memory);

    function getCurrentInboundCapacity(uint16 chainId) external view returns (uint256);

    function getInboundQueuedTransfer(bytes32 digest)
        external
        view
        returns (InboundQueuedTransfer memory);
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/NormalizedAmount.sol";
import "../libraries/EndpointStructs.sol";

interface IRateLimiter {
    error NotEnoughCapacity(uint256 currentCapacity, uint256 amount);
    error OutboundQueuedTransferNotFound(uint64 queueSequence);
    error OutboundQueuedTransferStillQueued(uint64 queueSequence, uint256 transferTimestamp);
    error InboundQueuedTransferNotFound(bytes32 digest);
    error InboundQueuedTransferStillQueued(bytes32 digest, uint256 transferTimestamp);
    error CapacityCannotExceedLimit(NormalizedAmount newCurrentCapacity, NormalizedAmount newLimit);

    struct RateLimitParams {
        NormalizedAmount limit;
        NormalizedAmount currentCapacity;
        uint64 lastTxTimestamp;
    }

    struct OutboundQueuedTransfer {
        bytes32 recipient;
        NormalizedAmount amount;
        uint64 txTimestamp;
        uint16 recipientChain;
        address sender;
        bytes endpointInstructions;
    }

    struct InboundQueuedTransfer {
        NormalizedAmount amount;
        uint64 txTimestamp;
        address recipient;
    }

    function rateLimitDuration() external view returns (uint64);

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

    function enqueueInboundTransfer(
        bytes32 digest,
        NormalizedAmount memory amount,
        address recipient
    ) external;

    function enqueueOutboundTransfer(
        uint64 sequence,
        NormalizedAmount memory amount,
        uint16 recipientChain,
        bytes32 recipient,
        address senderAddress,
        bytes memory endpointInstructions
    ) external;

    function isInboundAmountRateLimited(
        NormalizedAmount memory amount,
        uint16 chainId_
    ) external view returns (bool);

    function isOutboundAmountRateLimited(NormalizedAmount memory amount)
        external
        view
        returns (bool);

    function backfillInboundAmount(NormalizedAmount memory amount, uint16 chainId_) external;

    function consumeInboundAmount(NormalizedAmount memory amount, uint16 chainId_) external;

    function backfillOutboundAmount(NormalizedAmount memory amount) external;

    function consumeOutboundAmount(NormalizedAmount memory amount) external;

    function setInboundLimit(NormalizedAmount memory limit, uint16 chainId_) external;

    function setOutboundLimit(NormalizedAmount memory limit) external;

    function deleteFromInboundQueue(bytes32 digest) external;

    function deleteFromOutboundQueue(uint64 sequence) external;
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.0 <0.9.0;

import "../interfaces/IRateLimiter.sol";
import "../interfaces/IRateLimiterEvents.sol";
import "./EndpointHelpers.sol";
import "../libraries/NormalizedAmount.sol";

abstract contract RateLimiter is IRateLimiter, IRateLimiterEvents {
    using NormalizedAmountLib for NormalizedAmount;
    /**
     * @dev The duration it takes for the limits to fully replenish
     */

    uint64 public immutable rateLimitDuration;

    /// =============== STORAGE ===============================================

    bytes32 public constant OUTBOUND_LIMIT_PARAMS_SLOT =
        bytes32(uint256(keccak256("ntt.outboundLimitParams")) - 1);

    bytes32 public constant OUTBOUND_QUEUE_SLOT =
        bytes32(uint256(keccak256("ntt.outboundQueue")) - 1);

    bytes32 public constant INBOUND_LIMIT_PARAMS_SLOT =
        bytes32(uint256(keccak256("ntt.inboundLimitParams")) - 1);

    bytes32 public constant INBOUND_QUEUE_SLOT = bytes32(uint256(keccak256("ntt.inboundQueue")) - 1);

    function _getOutboundLimitParamsStorage() internal pure returns (RateLimitParams storage $) {
        uint256 slot = uint256(OUTBOUND_LIMIT_PARAMS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getOutboundQueueStorage()
        internal
        pure
        returns (mapping(uint64 => OutboundQueuedTransfer) storage $)
    {
        uint256 slot = uint256(OUTBOUND_QUEUE_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getInboundLimitParamsStorage()
        internal
        pure
        returns (mapping(uint16 => RateLimitParams) storage $)
    {
        uint256 slot = uint256(INBOUND_LIMIT_PARAMS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getInboundQueueStorage()
        internal
        pure
        returns (mapping(bytes32 => InboundQueuedTransfer) storage $)
    {
        uint256 slot = uint256(INBOUND_QUEUE_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    constructor(uint64 _rateLimitDuration) {
        rateLimitDuration = _rateLimitDuration;
    }

    function _setLimit(NormalizedAmount limit, RateLimitParams storage rateLimitParams) internal {
        NormalizedAmount oldLimit = rateLimitParams.limit;
        NormalizedAmount currentCapacity = _getCurrentCapacity(rateLimitParams);
        rateLimitParams.limit = limit;

        rateLimitParams.currentCapacity =
            _calculateNewCurrentCapacity(limit, oldLimit, currentCapacity);

        rateLimitParams.lastTxTimestamp = uint64(block.timestamp);
    }

    function _setOutboundLimit(NormalizedAmount limit) internal {
        _setLimit(limit, _getOutboundLimitParamsStorage());
    }

    function getOutboundLimitParams() public pure returns (RateLimitParams memory) {
        return _getOutboundLimitParamsStorage();
    }

    function getCurrentOutboundCapacity() public view returns (uint256) {
        NormalizedAmount normalizedCapacity = _getCurrentCapacity(getOutboundLimitParams());
        uint8 decimals = _tokenDecimals();
        return normalizedCapacity.denormalize(decimals);
    }

    function getOutboundQueuedTransfer(uint64 queueSequence)
        public
        view
        returns (OutboundQueuedTransfer memory)
    {
        return _getOutboundQueueStorage()[queueSequence];
    }

    function _setInboundLimit(NormalizedAmount limit, uint16 chainId_) internal {
        _setLimit(limit, _getInboundLimitParamsStorage()[chainId_]);
    }

    function getInboundLimitParams(uint16 chainId_) public view returns (RateLimitParams memory) {
        return _getInboundLimitParamsStorage()[chainId_];
    }

    function getCurrentInboundCapacity(uint16 chainId_) public view returns (uint256) {
        NormalizedAmount normalizedCapacity = _getCurrentCapacity(getInboundLimitParams(chainId_));
        uint8 decimals = _tokenDecimals();
        return normalizedCapacity.denormalize(decimals);
    }

    function getInboundQueuedTransfer(bytes32 digest)
        public
        view
        returns (InboundQueuedTransfer memory)
    {
        return _getInboundQueueStorage()[digest];
    }

    /**
     * @dev Gets the current capacity for a parameterized rate limits struct
     */
    function _getCurrentCapacity(RateLimitParams memory rateLimitParams)
        internal
        view
        returns (NormalizedAmount capacity)
    {
        uint64 timePassed = uint64(block.timestamp) - rateLimitParams.lastTxTimestamp;
        NormalizedAmount ratePerSecond = rateLimitParams.limit.div(rateLimitDuration);
        NormalizedAmount calculatedCapacity =
            rateLimitParams.currentCapacity + (ratePerSecond.mul(timePassed));

        return calculatedCapacity.min(rateLimitParams.limit);
    }

    /**
     * @dev Updates the current capacity
     *
     * @param newLimit The new limit
     * @param oldLimit The old limit
     * @param currentCapacity The current capacity
     */
    function _calculateNewCurrentCapacity(
        NormalizedAmount newLimit,
        NormalizedAmount oldLimit,
        NormalizedAmount currentCapacity
    ) internal pure returns (NormalizedAmount newCurrentCapacity) {
        NormalizedAmount difference;

        if (oldLimit > newLimit) {
            difference = oldLimit - newLimit;
            newCurrentCapacity = currentCapacity > difference
                ? currentCapacity - difference
                : NormalizedAmount.wrap(0);
        } else {
            difference = newLimit - oldLimit;
            newCurrentCapacity = currentCapacity + difference;
        }
    }

    function _consumeOutboundAmount(NormalizedAmount amount) internal {
        _consumeRateLimitAmount(
            amount, _getCurrentCapacity(getOutboundLimitParams()), _getOutboundLimitParamsStorage()
        );
    }

    function _consumeInboundAmount(NormalizedAmount amount, uint16 chainId_) internal {
        _consumeRateLimitAmount(
            amount,
            _getCurrentCapacity(getInboundLimitParams(chainId_)),
            _getInboundLimitParamsStorage()[chainId_]
        );
    }

    function _consumeRateLimitAmount(
        NormalizedAmount amount,
        NormalizedAmount capacity,
        RateLimitParams storage rateLimitParams
    ) internal {
        rateLimitParams.lastTxTimestamp = uint64(block.timestamp);
        rateLimitParams.currentCapacity = capacity - amount;
    }

    function _isOutboundAmountRateLimited(NormalizedAmount amount) internal view returns (bool) {
        return _isAmountRateLimited(_getCurrentCapacity(getOutboundLimitParams()), amount);
    }

    function _isInboundAmountRateLimited(
        NormalizedAmount amount,
        uint16 chainId_
    ) internal view returns (bool) {
        return _isAmountRateLimited(_getCurrentCapacity(getInboundLimitParams(chainId_)), amount);
    }

    function _isAmountRateLimited(
        NormalizedAmount capacity,
        NormalizedAmount amount
    ) internal pure returns (bool) {
        return capacity < amount;
    }

    function _enqueueOutboundTransfer(
        uint64 sequence,
        NormalizedAmount amount,
        uint16 recipientChain,
        bytes32 recipient
    ) internal {
        _getOutboundQueueStorage()[sequence] = OutboundQueuedTransfer({
            amount: amount,
            recipientChain: recipientChain,
            recipient: recipient,
            txTimestamp: uint64(block.timestamp)
        });

        emit OutboundTransferQueued(sequence);
    }

    function _enqueueInboundTransfer(
        bytes32 digest,
        NormalizedAmount amount,
        address recipient
    ) internal {
        _getInboundQueueStorage()[digest] = InboundQueuedTransfer({
            amount: amount,
            recipient: recipient,
            txTimestamp: uint64(block.timestamp)
        });

        emit InboundTransferQueued(digest);
    }

    function _tokenDecimals() internal view virtual returns (uint8);
}

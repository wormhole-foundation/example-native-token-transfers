// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../interfaces/IRateLimiter.sol";
import "../interfaces/IRateLimiterEvents.sol";
import "./TransceiverHelpers.sol";
import "./TransceiverStructs.sol";
import "../libraries/TrimmedAmount.sol";

abstract contract RateLimiter is IRateLimiter, IRateLimiterEvents {
    using TrimmedAmountLib for TrimmedAmount;
    /**
     * @dev The duration it takes for the limits to fully replenish
     */

    uint64 public immutable rateLimitDuration;

    /// =============== STORAGE ===============================================

    bytes32 private constant OUTBOUND_LIMIT_PARAMS_SLOT =
        bytes32(uint256(keccak256("ntt.outboundLimitParams")) - 1);

    bytes32 private constant OUTBOUND_QUEUE_SLOT =
        bytes32(uint256(keccak256("ntt.outboundQueue")) - 1);

    bytes32 private constant INBOUND_LIMIT_PARAMS_SLOT =
        bytes32(uint256(keccak256("ntt.inboundLimitParams")) - 1);

    bytes32 private constant INBOUND_QUEUE_SLOT =
        bytes32(uint256(keccak256("ntt.inboundQueue")) - 1);

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

    function _setLimit(
        TrimmedAmount memory limit,
        RateLimitParams storage rateLimitParams
    ) internal {
        TrimmedAmount memory oldLimit = rateLimitParams.limit;
        TrimmedAmount memory currentCapacity = _getCurrentCapacity(rateLimitParams);
        rateLimitParams.limit = limit;

        rateLimitParams.currentCapacity =
            _calculateNewCurrentCapacity(limit, oldLimit, currentCapacity);

        rateLimitParams.lastTxTimestamp = uint64(block.timestamp);
    }

    function _setOutboundLimit(TrimmedAmount memory limit) internal {
        _setLimit(limit, _getOutboundLimitParamsStorage());
    }

    function _getOutboundLimitParams() internal pure returns (RateLimitParams memory) {
        return _getOutboundLimitParamsStorage();
    }

    function getCurrentOutboundCapacity() public view returns (uint256) {
        TrimmedAmount memory trimmedCapacity = _getCurrentCapacity(_getOutboundLimitParams());
        uint8 decimals = tokenDecimals();
        return trimmedCapacity.untrim(decimals);
    }

    function getOutboundQueuedTransfer(uint64 queueSequence)
        public
        view
        returns (OutboundQueuedTransfer memory)
    {
        return _getOutboundQueueStorage()[queueSequence];
    }

    function _setInboundLimit(TrimmedAmount memory limit, uint16 chainId_) internal {
        _setLimit(limit, _getInboundLimitParamsStorage()[chainId_]);
    }

    function _getInboundLimitParams(uint16 chainId_)
        internal
        view
        returns (RateLimitParams memory)
    {
        return _getInboundLimitParamsStorage()[chainId_];
    }

    function getCurrentInboundCapacity(uint16 chainId_) public view returns (uint256) {
        TrimmedAmount memory trimmedCapacity = _getCurrentCapacity(_getInboundLimitParams(chainId_));
        uint8 decimals = tokenDecimals();
        return trimmedCapacity.untrim(decimals);
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
        returns (TrimmedAmount memory capacity)
    {
        // The capacity and rate limit are expressed as trimmed amounts, i.e.
        // 64-bit unsigned integers. The following operations upcast the 64-bit
        // unsigned integers to 256-bit unsigned integers to avoid overflow.
        // Specifically, the calculatedCapacity can overflow the u64 max.
        // For example, if the limit is uint64.max, then the multiplication in calculatedCapacity
        // will overflow when timePassed is greater than rateLimitDuration.
        // Operating on uint256 avoids this issue. The overflow is cancelled out by the min operation,
        // whose second argument is a uint64, so the result can safely be downcast to a uint64.
        unchecked {
            uint256 timePassed = block.timestamp - rateLimitParams.lastTxTimestamp;
            // Multiply (limit * timePassed), then divide by the duration.
            // Dividing first has terrible numerical stability --
            // when rateLimitDuration is close to the limit, there is significant rounding error.
            // We are safe to multiply first, since these numbers are u64 TrimmedAmount memory types
            // and we're performing arithmetic on u256 words.
            uint256 calculatedCapacity = rateLimitParams.currentCapacity.getAmount()
                + (rateLimitParams.limit.getAmount() * timePassed) / rateLimitDuration;

            uint256 result = min(calculatedCapacity, rateLimitParams.limit.getAmount());
            return TrimmedAmount(uint64(result), rateLimitParams.currentCapacity.getDecimals());
        }
    }

    /**
     * @dev Updates the current capacity
     *
     * @param newLimit The new limit
     * @param oldLimit The old limit
     * @param currentCapacity The current capacity
     */
    function _calculateNewCurrentCapacity(
        TrimmedAmount memory newLimit,
        TrimmedAmount memory oldLimit,
        TrimmedAmount memory currentCapacity
    ) internal pure returns (TrimmedAmount memory newCurrentCapacity) {
        TrimmedAmount memory difference;

        if (oldLimit.gt(newLimit)) {
            difference = oldLimit.sub(newLimit);
            newCurrentCapacity = currentCapacity.gt(difference)
                ? currentCapacity.sub(difference)
                : TrimmedAmount(0, currentCapacity.decimals);
        } else {
            difference = newLimit.sub(oldLimit);
            newCurrentCapacity = currentCapacity.add(difference);
        }

        if (newCurrentCapacity.gt(newLimit)) {
            revert CapacityCannotExceedLimit(newCurrentCapacity, newLimit);
        }
    }

    function _consumeOutboundAmount(TrimmedAmount memory amount) internal {
        _consumeRateLimitAmount(
            amount, _getCurrentCapacity(_getOutboundLimitParams()), _getOutboundLimitParamsStorage()
        );
    }

    function _backfillOutboundAmount(TrimmedAmount memory amount) internal {
        _backfillRateLimitAmount(
            amount, _getCurrentCapacity(_getOutboundLimitParams()), _getOutboundLimitParamsStorage()
        );
    }

    function _consumeInboundAmount(TrimmedAmount memory amount, uint16 chainId_) internal {
        _consumeRateLimitAmount(
            amount,
            _getCurrentCapacity(_getInboundLimitParams(chainId_)),
            _getInboundLimitParamsStorage()[chainId_]
        );
    }

    function _backfillInboundAmount(TrimmedAmount memory amount, uint16 chainId_) internal {
        _backfillRateLimitAmount(
            amount,
            _getCurrentCapacity(_getInboundLimitParams(chainId_)),
            _getInboundLimitParamsStorage()[chainId_]
        );
    }

    function _consumeRateLimitAmount(
        TrimmedAmount memory amount,
        TrimmedAmount memory capacity,
        RateLimitParams storage rateLimitParams
    ) internal {
        rateLimitParams.lastTxTimestamp = uint64(block.timestamp);
        rateLimitParams.currentCapacity = capacity.sub(amount);
    }

    /// @dev Refills the capacity by the given amount.
    /// This is used to replenish the capacity via backflows.
    function _backfillRateLimitAmount(
        TrimmedAmount memory amount,
        TrimmedAmount memory capacity,
        RateLimitParams storage rateLimitParams
    ) internal {
        rateLimitParams.lastTxTimestamp = uint64(block.timestamp);
        rateLimitParams.currentCapacity = capacity.add(amount).min(rateLimitParams.limit);
    }

    function _isOutboundAmountRateLimited(TrimmedAmount memory amount)
        internal
        view
        returns (bool)
    {
        return _isAmountRateLimited(_getCurrentCapacity(_getOutboundLimitParams()), amount);
    }

    function _isInboundAmountRateLimited(
        TrimmedAmount memory amount,
        uint16 chainId_
    ) internal view returns (bool) {
        return _isAmountRateLimited(_getCurrentCapacity(_getInboundLimitParams(chainId_)), amount);
    }

    function _isAmountRateLimited(
        TrimmedAmount memory capacity,
        TrimmedAmount memory amount
    ) internal pure returns (bool) {
        return capacity.lt(amount);
    }

    function _enqueueOutboundTransfer(
        uint64 sequence,
        TrimmedAmount memory amount,
        uint16 recipientChain,
        bytes32 recipient,
        address senderAddress,
        bytes memory transceiverInstructions
    ) internal {
        _getOutboundQueueStorage()[sequence] = OutboundQueuedTransfer({
            amount: amount,
            recipientChain: recipientChain,
            recipient: recipient,
            txTimestamp: uint64(block.timestamp),
            sender: senderAddress,
            transceiverInstructions: transceiverInstructions
        });

        emit OutboundTransferQueued(sequence);
    }

    function _enqueueInboundTransfer(
        bytes32 digest,
        TrimmedAmount memory amount,
        address recipient
    ) internal {
        _getInboundQueueStorage()[digest] = InboundQueuedTransfer({
            amount: amount,
            recipient: recipient,
            txTimestamp: uint64(block.timestamp)
        });

        emit InboundTransferQueued(digest);
    }

    function tokenDecimals() public view virtual returns (uint8);
}

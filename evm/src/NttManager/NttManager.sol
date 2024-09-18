// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "../libraries/RateLimiter.sol";

import "../interfaces/INttManager.sol";
import "../interfaces/INttToken.sol";
import "../interfaces/ITransceiver.sol";

import {ManagerBase} from "./ManagerBase.sol";
import {NttManagerBase} from "./NttManagerBase.sol";

/// @title NttManager
/// @author Wormhole Project Contributors.
/// @notice The NttManager contract is responsible for managing the token
///         and associated transceivers. It uses the rate limiter.
///
/// @dev Each NttManager contract is associated with a single token but
///      can be responsible for multiple transceivers.
///
/// @dev When transferring tokens, the NttManager contract will either
///      lock the tokens or burn them, depending on the mode.
///
/// @dev To initiate a transfer, the user calls the transfer function with:
///  - the amount
///  - the recipient chain
///  - the recipient address
///  - the refund address: the address to which refunds are issued for any unused gas
///    for attestations on a given transfer. If the gas limit is configured
///    to be too high, users will be refunded the difference.
///  - (optional) a flag to indicate whether the transfer should be queued
///    if the rate limit is exceeded
contract NttManager is NttManagerBase, RateLimiter {
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;
    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    string public constant NTT_MANAGER_VERSION = "1.1.0";

    // =============== Setup =================================================================

    constructor(
        address _token,
        Mode _mode,
        uint16 _chainId,
        uint64 _rateLimitDuration,
        bool _skipRateLimiting
    ) RateLimiter(_rateLimitDuration, _skipRateLimiting) NttManagerBase(_token, _mode, _chainId) {}

    function __NttManager_init() internal override onlyInitializing {
        super.__NttManager_init();
        _setOutboundLimit(TrimmedAmountLib.max(tokenDecimals()));
    }

    // =============== Admin ==============================================================

    /// @inheritdoc INttManager
    function setPeer(
        uint16 peerChainId,
        bytes32 peerContract,
        uint8 decimals,
        uint256 inboundLimit
    ) public override onlyOwner {
        super.setPeer(peerChainId, peerContract, decimals, inboundLimit);

        uint8 toDecimals = tokenDecimals();
        _setInboundLimit(inboundLimit.trim(toDecimals, toDecimals), peerChainId);
    }

    /// @inheritdoc INttManager
    function setOutboundLimit(
        uint256 limit
    ) external override onlyOwner {
        uint8 toDecimals = tokenDecimals();
        _setOutboundLimit(limit.trim(toDecimals, toDecimals));
    }

    /// @inheritdoc INttManager
    function setInboundLimit(uint256 limit, uint16 chainId_) external override onlyOwner {
        uint8 toDecimals = tokenDecimals();
        _setInboundLimit(limit.trim(toDecimals, toDecimals), chainId_);
    }

    /// ============== Invariants =============================================

    /// @dev When we add new immutables, this function should be updated
    function _checkImmutables() internal view override {
        super._checkImmutables();
        assert(this.rateLimitDuration() == rateLimitDuration);
    }

    // ==================== External Interface ===============================================

    /// @inheritdoc INttManager
    function executeMsg(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory message
    ) public override whenNotPaused {
        (
            bytes32 digest,
            bool alreadyExecuted,
            address transferRecipient,
            TrimmedAmount nativeTransferAmount
        ) = super._executeMsg1(sourceChainId, sourceNttManagerAddress, message);
        if (alreadyExecuted) {
            return;
        }

        {
            // Check inbound rate limits
            bool isRateLimited = _isInboundAmountRateLimited(nativeTransferAmount, sourceChainId);
            if (isRateLimited) {
                // queue up the transfer
                _enqueueInboundTransfer(digest, nativeTransferAmount, transferRecipient);

                // end execution early
                return;
            }
        }

        // consume the amount for the inbound rate limit
        _consumeInboundAmount(nativeTransferAmount, sourceChainId);
        // When receiving a transfer, we refill the outbound rate limit
        // by the same amount (we call this "backflow")
        _backfillOutboundAmount(nativeTransferAmount);

        super._executeMsg2(digest, transferRecipient, nativeTransferAmount);
    }

    /// @inheritdoc INttManager
    function completeInboundQueuedTransfer(
        bytes32 digest
    ) external override nonReentrant whenNotPaused {
        // find the message in the queue
        InboundQueuedTransfer memory queuedTransfer = getInboundQueuedTransfer(digest);
        if (queuedTransfer.txTimestamp == 0) {
            revert InboundQueuedTransferNotFound(digest);
        }

        // check that > RATE_LIMIT_DURATION has elapsed
        if (block.timestamp - queuedTransfer.txTimestamp < rateLimitDuration) {
            revert InboundQueuedTransferStillQueued(digest, queuedTransfer.txTimestamp);
        }

        // remove transfer from the queue
        delete _getInboundQueueStorage()[digest];

        // run it through the mint/unlock logic
        _mintOrUnlockToRecipient(digest, queuedTransfer.recipient, queuedTransfer.amount, false);
    }

    /// @inheritdoc INttManager
    function completeOutboundQueuedTransfer(
        uint64 messageSequence
    ) external payable override nonReentrant whenNotPaused returns (uint64) {
        // find the message in the queue
        OutboundQueuedTransfer memory queuedTransfer = _getOutboundQueueStorage()[messageSequence];
        if (queuedTransfer.txTimestamp == 0) {
            revert OutboundQueuedTransferNotFound(messageSequence);
        }

        // check that > RATE_LIMIT_DURATION has elapsed
        if (block.timestamp - queuedTransfer.txTimestamp < rateLimitDuration) {
            revert OutboundQueuedTransferStillQueued(messageSequence, queuedTransfer.txTimestamp);
        }

        // remove transfer from the queue
        delete _getOutboundQueueStorage()[messageSequence];

        // run it through the transfer logic and skip the rate limit
        return _transfer(
            messageSequence,
            queuedTransfer.amount,
            queuedTransfer.recipientChain,
            queuedTransfer.recipient,
            queuedTransfer.refundAddress,
            queuedTransfer.sender,
            queuedTransfer.transceiverInstructions
        );
    }

    /// @inheritdoc INttManager
    function cancelOutboundQueuedTransfer(
        uint64 messageSequence
    ) external override nonReentrant whenNotPaused {
        // find the message in the queue
        OutboundQueuedTransfer memory queuedTransfer = _getOutboundQueueStorage()[messageSequence];
        if (queuedTransfer.txTimestamp == 0) {
            revert OutboundQueuedTransferNotFound(messageSequence);
        }

        // check msg.sender initiated the transfer
        if (queuedTransfer.sender != msg.sender) {
            revert CancellerNotSender(msg.sender, queuedTransfer.sender);
        }

        // remove transfer from the queue
        delete _getOutboundQueueStorage()[messageSequence];

        // return the queued funds to the sender
        _mintOrUnlockToRecipient(
            bytes32(uint256(messageSequence)), msg.sender, queuedTransfer.amount, true
        );
    }

    // ==================== Internal Business Logic =========================================

    function _transferEntryPoint(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bytes32 refundAddress,
        bool shouldQueue,
        bytes memory transceiverInstructions
    ) internal override returns (uint64) {
        (uint64 sequence, TrimmedAmount trimmedAmount) =
            _transferEntryPoint1(amount, recipientChain, recipient, refundAddress);

        TrimmedAmount internalAmount = trimmedAmount.shift(tokenDecimals());
        {
            // now check rate limits
            bool isAmountRateLimited = _isOutboundAmountRateLimited(internalAmount);
            if (!shouldQueue && isAmountRateLimited) {
                revert NotEnoughCapacity(getCurrentOutboundCapacity(), amount);
            }
            if (shouldQueue && isAmountRateLimited) {
                // verify chain has not forked
                checkFork(evmChainId);

                // emit an event to notify the user that the transfer is rate limited
                emit OutboundTransferRateLimited(
                    msg.sender, sequence, amount, getCurrentOutboundCapacity()
                );

                // queue up and return
                _enqueueOutboundTransfer(
                    sequence,
                    trimmedAmount,
                    recipientChain,
                    recipient,
                    refundAddress,
                    msg.sender,
                    transceiverInstructions
                );

                // refund price quote back to sender
                _refundToSender(msg.value);

                // return the sequence in the queue
                return sequence;
            }
        }

        // otherwise, consume the outbound amount
        _consumeOutboundAmount(internalAmount);
        // When sending a transfer, we refill the inbound rate limit for
        // that chain by the same amount (we call this "backflow")
        _backfillInboundAmount(internalAmount, recipientChain);

        return _transfer(
            sequence,
            trimmedAmount,
            recipientChain,
            recipient,
            refundAddress,
            msg.sender,
            transceiverInstructions
        );
    }

    function tokenDecimals() public view override(NttManagerBase, RateLimiter) returns (uint8) {
        return NttManagerBase.tokenDecimals();
    }
}

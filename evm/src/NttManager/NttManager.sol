// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "../libraries/RateLimiter.sol";

import "../interfaces/INttManager.sol";
import "../interfaces/INttManagerEvents.sol";
import "../interfaces/INTTToken.sol";
import "../interfaces/ITransceiver.sol";

import {NttManagerState} from "./NttManagerState.sol";

contract NttManager is INttManager, NttManagerState {
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;
    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    constructor(
        address _token,
        Mode _mode,
        uint16 _chainId,
        uint64 _rateLimitDuration,
        bool _skipRateLimiting
    ) NttManagerState(_token, _mode, _chainId, _rateLimitDuration, _skipRateLimiting) {}

    // ==================== External Interface ===============================================

    /// @inheritdoc INttManager
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) external payable nonReentrant whenNotPaused returns (uint64) {
        return _transferEntryPoint(amount, recipientChain, recipient, false, new bytes(1));
    }

    /// @inheritdoc INttManager
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bool shouldQueue,
        bytes memory transceiverInstructions
    ) external payable nonReentrant whenNotPaused returns (uint64) {
        return _transferEntryPoint(
            amount, recipientChain, recipient, shouldQueue, transceiverInstructions
        );
    }

    /// @inheritdoc INttManager
    function quoteDeliveryPrice(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction[] memory transceiverInstructions,
        address[] memory enabledTransceivers
    ) public view returns (uint256[] memory, uint256) {
        uint256 numEnabledTransceivers = enabledTransceivers.length;
        mapping(address => TransceiverInfo) storage transceiverInfos = _getTransceiverInfosStorage();

        uint256[] memory priceQuotes = new uint256[](numEnabledTransceivers);
        uint256 totalPriceQuote = 0;
        for (uint256 i = 0; i < numEnabledTransceivers; i++) {
            address transceiverAddr = enabledTransceivers[i];
            uint8 registeredTransceiverIndex = transceiverInfos[transceiverAddr].index;
            uint256 transceiverPriceQuote = ITransceiver(transceiverAddr).quoteDeliveryPrice(
                recipientChain, transceiverInstructions[registeredTransceiverIndex]
            );
            priceQuotes[i] = transceiverPriceQuote;
            totalPriceQuote += transceiverPriceQuote;
        }
        return (priceQuotes, totalPriceQuote);
    }

    /// @inheritdoc INttManager
    function attestationReceived(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory payload
    ) external onlyTransceiver {
        _verifyPeer(sourceChainId, sourceNttManagerAddress);

        bytes32 nttManagerMessageHash =
            TransceiverStructs.nttManagerMessageDigest(sourceChainId, payload);

        // set the attested flag for this transceiver.
        // NOTE: Attestation is idempotent (bitwise or 1), but we revert
        // anyway to ensure that the client does not continue to initiate calls
        // to receive the same message through the same transceiver.
        if (
            transceiverAttestedToMessage(
                nttManagerMessageHash, _getTransceiverInfosStorage()[msg.sender].index
            )
        ) {
            revert TransceiverAlreadyAttestedToMessage(nttManagerMessageHash);
        }
        _setTransceiverAttestedToMessage(nttManagerMessageHash, msg.sender);

        if (isMessageApproved(nttManagerMessageHash)) {
            executeMsg(sourceChainId, sourceNttManagerAddress, payload);
        }
    }

    /// @inheritdoc INttManager
    function executeMsg(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory message
    ) public {
        // verify chain has not forked
        checkFork(evmChainId);

        bytes32 digest = TransceiverStructs.nttManagerMessageDigest(sourceChainId, message);

        if (!isMessageApproved(digest)) {
            revert MessageNotApproved(digest);
        }

        bool msgAlreadyExecuted = _replayProtect(digest);
        if (msgAlreadyExecuted) {
            // end execution early to mitigate the possibility of race conditions from transceivers
            // attempting to deliver the same message when (threshold < number of transceiver messages)
            // notify client (off-chain process) so they don't attempt redundant msg delivery
            emit MessageAlreadyExecuted(sourceNttManagerAddress, digest);
            return;
        }

        TransceiverStructs.NativeTokenTransfer memory nativeTokenTransfer =
            TransceiverStructs.parseNativeTokenTransfer(message.payload);

        // verify that the destination chain is valid
        if (nativeTokenTransfer.toChain != chainId) {
            revert InvalidTargetChain(nativeTokenTransfer.toChain, chainId);
        }
        TrimmedAmount memory nativeTransferAmount =
            (nativeTokenTransfer.amount.untrim(tokenDecimals_)).trim(tokenDecimals_, tokenDecimals_);

        address transferRecipient = fromWormholeFormat(nativeTokenTransfer.to);

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

        _mintOrUnlockToRecipient(digest, transferRecipient, nativeTransferAmount);
    }

    /// @inheritdoc INttManager
    function completeInboundQueuedTransfer(bytes32 digest) external nonReentrant whenNotPaused {
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
        _mintOrUnlockToRecipient(digest, queuedTransfer.recipient, queuedTransfer.amount);
    }

    /// @inheritdoc INttManager
    function completeOutboundQueuedTransfer(uint64 messageSequence)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint64)
    {
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
            queuedTransfer.sender,
            queuedTransfer.transceiverInstructions
        );
    }

    // ==================== Internal Business Logic =========================================

    function _sendMessageToTransceivers(
        uint16 recipientChain,
        uint256[] memory priceQuotes,
        TransceiverStructs.TransceiverInstruction[] memory transceiverInstructions,
        address[] memory enabledTransceivers,
        bytes memory nttManagerMessage
    ) internal {
        uint256 numEnabledTransceivers = enabledTransceivers.length;
        mapping(address => TransceiverInfo) storage transceiverInfos = _getTransceiverInfosStorage();
        bytes32 peerAddress = _getPeersStorage()[recipientChain].peerAddress;
        // call into transceiver contracts to send the message
        for (uint256 i = 0; i < numEnabledTransceivers; i++) {
            address transceiverAddr = enabledTransceivers[i];
            // send it to the recipient nttManager based on the chain
            ITransceiver(transceiverAddr).sendMessage{value: priceQuotes[i]}(
                recipientChain,
                transceiverInstructions[transceiverInfos[transceiverAddr].index],
                nttManagerMessage,
                peerAddress
            );
        }
    }

    function _transferEntryPoint(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bool shouldQueue,
        bytes memory transceiverInstructions
    ) internal returns (uint64) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (recipient == bytes32(0)) {
            revert InvalidRecipient();
        }

        {
            // Lock/burn tokens before checking rate limits
            if (mode == Mode.LOCKING) {
                {
                    // use transferFrom to pull tokens from the user and lock them
                    // query own token balance before transfer
                    uint256 balanceBefore = _getTokenBalanceOf(token, address(this));

                    // transfer tokens
                    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

                    // query own token balance after transfer
                    uint256 balanceAfter = _getTokenBalanceOf(token, address(this));

                    // correct amount for potential transfer fees
                    amount = balanceAfter - balanceBefore;
                }
            } else if (mode == Mode.BURNING) {
                {
                    // query sender's token balance before burn
                    uint256 balanceBefore = _getTokenBalanceOf(token, msg.sender);

                    // call the token's burn function to burn the sender's token
                    // NOTE: We don't account for burn fees in this code path.
                    // We verify that the user's change in balance is equal to the amount that's burned.
                    // Accounting for burn fees can be non-trivial, since there
                    // is no standard way to account for the fee if the fee amount
                    // is taken out of the burn amount.
                    // For example, if there's a fee of 1 which is taken out of the
                    // amount, then burning 20 tokens would result in a transfer of only 19 tokens.
                    // However, the difference in the user's balance would only show 20.
                    // Since there is no standard way to query for burn fee amounts with burnable tokens,
                    // and NTT would be used on a per-token basis, implementing this functionality
                    // is left to integrating projects who may need to account for burn fees on their tokens.
                    ERC20Burnable(token).burnFrom(msg.sender, amount);

                    // query sender's token balance after transfer
                    uint256 balanceAfter = _getTokenBalanceOf(token, msg.sender);

                    uint256 balanceDiff = balanceBefore - balanceAfter;
                    if (balanceDiff != amount) {
                        revert BurnAmountDifferentThanBalanceDiff(amount, balanceDiff);
                    }
                }
            } else {
                revert InvalidMode(uint8(mode));
            }
        }

        // trim amount after burning to ensure transfer amount matches (amount - fee)
        TrimmedAmount memory trimmedAmount = _trimTransferAmount(amount, recipientChain);
        TrimmedAmount memory internalAmount = trimmedAmount.shift(tokenDecimals_);

        // get the sequence for this transfer
        uint64 sequence = _useMessageSequence();

        {
            // now check rate limits
            bool isAmountRateLimited = _isOutboundAmountRateLimited(internalAmount);
            if (!shouldQueue && isAmountRateLimited) {
                revert NotEnoughCapacity(getCurrentOutboundCapacity(), amount);
            }
            if (shouldQueue && isAmountRateLimited) {
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
            sequence, trimmedAmount, recipientChain, recipient, msg.sender, transceiverInstructions
        );
    }

    function _transfer(
        uint64 sequence,
        TrimmedAmount memory amount,
        uint16 recipientChain,
        bytes32 recipient,
        address sender,
        bytes memory transceiverInstructions
    ) internal returns (uint64 msgSequence) {
        // cache enabled transceivers to avoid multiple storage reads
        address[] memory enabledTransceivers = _getEnabledTransceiversStorage();

        TransceiverStructs.TransceiverInstruction[] memory instructions = TransceiverStructs
            .parseTransceiverInstructions(transceiverInstructions, enabledTransceivers.length);

        (uint256[] memory priceQuotes, uint256 totalPriceQuote) =
            quoteDeliveryPrice(recipientChain, instructions, enabledTransceivers);
        {
            // check up front that msg.value will cover the delivery price
            if (msg.value < totalPriceQuote) {
                revert DeliveryPaymentTooLow(totalPriceQuote, msg.value);
            }

            // refund user extra excess value from msg.value
            uint256 excessValue = msg.value - totalPriceQuote;
            if (excessValue > 0) {
                _refundToSender(excessValue);
            }
        }

        // push it on the stack again to avoid a stack too deep error
        uint64 seq = sequence;

        TransceiverStructs.NativeTokenTransfer memory ntt = TransceiverStructs.NativeTokenTransfer(
            amount, toWormholeFormat(token), recipient, recipientChain
        );

        // construct the NttManagerMessage payload
        bytes memory encodedNttManagerPayload = TransceiverStructs.encodeNttManagerMessage(
            TransceiverStructs.NttManagerMessage(
                seq, toWormholeFormat(sender), TransceiverStructs.encodeNativeTokenTransfer(ntt)
            )
        );

        // send the message
        _sendMessageToTransceivers(
            recipientChain, priceQuotes, instructions, enabledTransceivers, encodedNttManagerPayload
        );

        // push it on the stack again to avoid a stack too deep error
        TrimmedAmount memory amt = amount;
        uint16 destinationChain = recipientChain;

        emit TransferSent(
            recipient, amt.untrim(tokenDecimals_), totalPriceQuote, destinationChain, seq
        );

        // return the sequence number
        return sequence;
    }

    function _mintOrUnlockToRecipient(
        bytes32 digest,
        address recipient,
        TrimmedAmount memory amount
    ) internal {
        // calculate proper amount of tokens to unlock/mint to recipient
        // untrim the amount
        uint256 untrimmedAmount = amount.untrim(tokenDecimals_);

        emit TransferRedeemed(digest);

        if (mode == Mode.LOCKING) {
            // unlock tokens to the specified recipient
            IERC20(token).safeTransfer(recipient, untrimmedAmount);
        } else if (mode == Mode.BURNING) {
            // mint tokens to the specified recipient
            INTTToken(token).mint(recipient, untrimmedAmount);
        } else {
            revert InvalidMode(uint8(mode));
        }
    }

    /// @inheritdoc INttManager
    function tokenDecimals() public view override(INttManager, RateLimiter) returns (uint8) {
        return tokenDecimals_;
    }

    // ==================== Internal Helpers ===============================================

    function _refundToSender(uint256 refundAmount) internal {
        // refund the price quote back to sender
        (bool refundSuccessful,) = payable(msg.sender).call{value: refundAmount}("");

        // check success
        if (!refundSuccessful) {
            revert RefundFailed(refundAmount);
        }
    }

    function _trimTransferAmount(
        uint256 amount,
        uint16 toChain
    ) internal view returns (TrimmedAmount memory) {
        uint8 toDecimals = _getPeersStorage()[toChain].tokenDecimals;

        if (toDecimals == 0) {
            revert InvalidPeerDecimals();
        }

        TrimmedAmount memory trimmedAmount;
        {
            trimmedAmount = amount.trim(tokenDecimals_, toDecimals);
            // don't deposit dust that can not be bridged due to the decimal shift
            uint256 newAmount = trimmedAmount.untrim(tokenDecimals_);
            if (amount != newAmount) {
                revert TransferAmountHasDust(amount, amount - newAmount);
            }
        }

        return trimmedAmount;
    }

    function _getTokenBalanceOf(
        address tokenAddr,
        address accountAddr
    ) internal view returns (uint256) {
        (, bytes memory queriedBalance) =
            tokenAddr.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, accountAddr));
        return abi.decode(queriedBalance, (uint256));
    }
}

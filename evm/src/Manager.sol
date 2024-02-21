// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "./libraries/external/OwnableUpgradeable.sol";
import "./libraries/external/ReentrancyGuardUpgradeable.sol";
import "./libraries/EndpointStructs.sol";
import "./libraries/EndpointHelpers.sol";
import "./libraries/RateLimiter.sol";
import "./interfaces/IManager.sol";
import "./interfaces/IManagerEvents.sol";
import "./interfaces/INTTToken.sol";
import "./Endpoint.sol";
import "./EndpointRegistry.sol";
import "./NttNormalizer.sol";
import "./libraries/PausableOwnable.sol";

// TODO: rename this (it's really the business logic)
abstract contract Manager is
    IManager,
    IManagerEvents,
    EndpointRegistry,
    RateLimiter,
    NttNormalizer,
    ReentrancyGuardUpgradeable,
    PausableOwnable
{
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;

    error RefundFailed(uint256 refundAmount);
    error CannotRenounceManagerOwnership(address owner);
    error UnexpectedOwner(address expectedOwner, address owner);

    address public immutable token;
    address public immutable deployer;
    Mode public immutable mode;
    uint16 public immutable chainId;
    uint256 public immutable evmChainId;

    enum Mode {
        LOCKING,
        BURNING
    }

    // @dev Information about attestations for a given message.
    struct AttestationInfo {
        // whether this message has been executed
        bool executed;
        // bitmap of endpoints that have attested to this message (NOTE: might contain disabled endpoints)
        uint64 attestedEndpoints;
    }

    struct _Sequence {
        uint64 num;
    }

    /// =============== STORAGE ===============================================

    bytes32 public constant MESSAGE_ATTESTATIONS_SLOT =
        bytes32(uint256(keccak256("ntt.messageAttestations")) - 1);

    bytes32 public constant MESSAGE_SEQUENCE_SLOT =
        bytes32(uint256(keccak256("ntt.messageSequence")) - 1);

    bytes32 public constant SIBLINGS_SLOT = bytes32(uint256(keccak256("ntt.siblings")) - 1);

    function _getMessageAttestationsStorage()
        internal
        pure
        returns (mapping(bytes32 => AttestationInfo) storage $)
    {
        uint256 slot = uint256(MESSAGE_ATTESTATIONS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getMessageSequenceStorage() internal pure returns (_Sequence storage $) {
        uint256 slot = uint256(MESSAGE_SEQUENCE_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getSiblingsStorage() internal pure returns (mapping(uint16 => bytes32) storage $) {
        uint256 slot = uint256(SIBLINGS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    constructor(
        address _token,
        Mode _mode,
        uint16 _chainId,
        uint64 _rateLimitDuration
    ) RateLimiter(_rateLimitDuration) NttNormalizer(_token) {
        token = _token;
        mode = _mode;
        chainId = _chainId;
        evmChainId = block.chainid;
        // save the deployer (check this on iniitialization)
        deployer = msg.sender;
    }

    function __Manager_init() internal onlyInitializing {
        // check if the owner is the deployer of this contract
        if (msg.sender != deployer) {
            revert UnexpectedOwner(deployer, msg.sender);
        }
        // TODO: msg.sender may not be the right address for both
        __PausedOwnable_init(msg.sender, msg.sender);
        // TODO: check if it's safe to not initialise reentrancy guard
        __ReentrancyGuard_init();
    }

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    ///      This method should return an array of delivery prices corresponding to each endpoint.
    function quoteDeliveryPrice(
        uint16 recipientChain,
        EndpointStructs.EndpointInstruction[] memory endpointInstructions
    ) public view virtual returns (uint256[] memory);

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function _sendMessageToEndpoints(
        uint16 recipientChain,
        uint256[] memory priceQuotes,
        EndpointStructs.EndpointInstruction[] memory endpointInstructions,
        bytes memory managerMessage
    ) internal virtual;

    // TODO: do we want additional information (like chain etc)
    function isMessageApproved(bytes32 digest) public view virtual returns (bool);

    function _setEndpointAttestedToMessage(bytes32 digest, uint8 index) internal {
        _getMessageAttestationsStorage()[digest].attestedEndpoints |= uint64(1 << index);
    }

    function _setEndpointAttestedToMessage(bytes32 digest, address endpoint) internal {
        _setEndpointAttestedToMessage(digest, _getEndpointInfosStorage()[endpoint].index);

        emit MessageAttestedTo(digest, endpoint, _getEndpointInfosStorage()[endpoint].index);
    }

    /*
     * @dev pause the Endpoint.
     */
    function pause() public virtual onlyOwnerOrPauser {
        _pause();
    }

    /// @dev Returns the bitmap of attestations from enabled endpoints for a given message.
    function _getMessageAttestations(bytes32 digest) internal view returns (uint64) {
        uint64 enabledEndpointBitmap = _getEnabledEndpointsBitmap();
        return _getMessageAttestationsStorage()[digest].attestedEndpoints & enabledEndpointBitmap;
    }

    function _getEnabledEndpointAttestedToMessage(
        bytes32 digest,
        uint8 index
    ) internal view returns (bool) {
        return _getMessageAttestations(digest) & uint64(1 << index) != 0;
    }

    function setOutboundLimit(uint256 limit) external onlyOwner {
        _setOutboundLimit(nttNormalize(limit));
    }

    function setInboundLimit(uint256 limit, uint16 chainId_) external onlyOwner {
        _setInboundLimit(nttNormalize(limit), chainId_);
    }

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
            queuedTransfer.endpointInstructions
        );
    }

    /// @dev Refunds the remaining amount back to the sender.
    function refundToSender(uint256 refundAmount) internal {
        // refund the price quote back to sender
        (bool refundSuccessful,) = payable(msg.sender).call{value: refundAmount}("");

        // check success
        if (!refundSuccessful) {
            revert RefundFailed(refundAmount);
        }
    }

    /// @dev Returns normalized amount and checks for dust
    function normalizeTransferAmount(uint256 amount)
        internal
        view
        returns (NormalizedAmount memory)
    {
        NormalizedAmount memory normalizedAmount;
        {
            normalizedAmount = nttNormalize(amount);
            // don't deposit dust that can not be bridged due to the decimal shift
            uint256 newAmount = nttDenormalize(normalizedAmount);
            if (amount != newAmount) {
                revert TransferAmountHasDust(amount, amount - newAmount);
            }
        }

        return normalizedAmount;
    }

    /// @dev Simple quality of life transfer method that doesn't deal with queuing or passing endpoint instructions.
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) external payable nonReentrant whenNotPaused returns (uint64) {
        return _transferEntryPoint(amount, recipientChain, recipient, false, new bytes(1));
    }

    /// @notice Called by the user to send the token cross-chain.
    ///         This function will either lock or burn the sender's tokens.
    ///         Finally, this function will call into the Endpoint contracts to send a message with the incrementing sequence number and the token transfer payload.
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bool shouldQueue,
        bytes memory endpointInstructions
    ) external payable nonReentrant whenNotPaused returns (uint64) {
        return _transferEntryPoint(
            amount, recipientChain, recipient, shouldQueue, endpointInstructions
        );
    }

    function _transferEntryPoint(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bool shouldQueue,
        bytes memory endpointInstructions
    ) internal returns (uint64) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        // parse the instructions up front to ensure they:
        // - are encoded correctly
        // - follow payload length restrictions
        EndpointStructs.parseEndpointInstructions(endpointInstructions);

        {
            // Lock/burn tokens before checking rate limits
            if (mode == Mode.LOCKING) {
                {
                    // use transferFrom to pull tokens from the user and lock them
                    // query own token balance before transfer
                    uint256 balanceBefore = getTokenBalanceOf(token, address(this));

                    // transfer tokens
                    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

                    // query own token balance after transfer
                    uint256 balanceAfter = getTokenBalanceOf(token, address(this));

                    // correct amount for potential transfer fees
                    amount = balanceAfter - balanceBefore;
                }
            } else if (mode == Mode.BURNING) {
                {
                    // query sender's token balance before burn
                    uint256 balanceBefore = getTokenBalanceOf(token, msg.sender);

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
                    uint256 balanceAfter = getTokenBalanceOf(token, msg.sender);

                    uint256 balanceDiff = balanceBefore - balanceAfter;
                    if (balanceDiff != amount) {
                        revert BurnAmountDifferentThanBalanceDiff(amount, balanceDiff);
                    }
                }
            } else {
                revert InvalidMode(uint8(mode));
            }
        }

        // normalize amount after burning to ensure transfer amount matches (amount - fee)
        NormalizedAmount memory normalizedAmount = normalizeTransferAmount(amount);

        // get the sequence for this transfer
        uint64 sequence = _useMessageSequence();

        {
            // now check rate limits
            bool isAmountRateLimited = _isOutboundAmountRateLimited(normalizedAmount);
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
                    normalizedAmount,
                    recipientChain,
                    recipient,
                    msg.sender,
                    endpointInstructions
                );

                // refund price quote back to sender
                refundToSender(msg.value);

                // return the sequence in the queue
                return sequence;
            }
        }

        // otherwise, consume the outbound amount
        _consumeOutboundAmount(normalizedAmount);
        // When sending a transfer, we refill the inbound rate limit for
        // that chain by the same amount (we call this "backflow")
        _backfillInboundAmount(normalizedAmount, recipientChain);

        return _transfer(
            sequence, normalizedAmount, recipientChain, recipient, msg.sender, endpointInstructions
        );
    }

    function _transfer(
        uint64 sequence,
        NormalizedAmount memory amount,
        uint16 recipientChain,
        bytes32 recipient,
        address sender,
        bytes memory endpointInstructions
    ) internal returns (uint64 msgSequence) {
        // parse and reorganize the endpoint instructions based on index
        EndpointStructs.EndpointInstruction[] memory sortedInstructions = EndpointStructs
            .sortEndpointInstructions(EndpointStructs.parseEndpointInstructions(endpointInstructions));

        uint256[] memory priceQuotes = quoteDeliveryPrice(recipientChain, sortedInstructions);
        {
            // check up front that msg.value will cover the delivery price
            uint256 totalPriceQuote = arraySum(priceQuotes);
            if (msg.value < totalPriceQuote) {
                revert DeliveryPaymentTooLow(totalPriceQuote, msg.value);
            }

            // refund user extra excess value from msg.value
            uint256 excessValue = msg.value - totalPriceQuote;
            if (excessValue > 0) {
                refundToSender(excessValue);
            }
        }

        bytes memory encodedTransferPayload = EndpointStructs.encodeNativeTokenTransfer(
            EndpointStructs.NativeTokenTransfer(
                amount, toWormholeFormat(token), recipient, recipientChain
            )
        );

        // construct the ManagerMessage payload
        bytes memory encodedManagerPayload = EndpointStructs.encodeManagerMessage(
            EndpointStructs.ManagerMessage(
                sequence, toWormholeFormat(sender), encodedTransferPayload
            )
        );

        // send the message
        _sendMessageToEndpoints(
            recipientChain, priceQuotes, sortedInstructions, encodedManagerPayload
        );

        emit TransferSent(recipient, nttDenormalize(amount), recipientChain, sequence);

        // return the sequence number
        return sequence;
    }

    /// @dev Verify that the sibling address saved for `sourceChainId` matches the `siblingAddress`.
    function _verifySibling(uint16 sourceChainId, bytes32 siblingAddress) internal view {
        if (getSibling(sourceChainId) != siblingAddress) {
            revert InvalidSibling(sourceChainId, siblingAddress);
        }
    }

    // @dev Mark a message as executed.
    // This function will retuns `true` if the message has already been executed.
    function _replayProtect(bytes32 digest) internal returns (bool) {
        // check if this message has already been executed
        if (isMessageExecuted(digest)) {
            return true;
        }

        // mark this message as executed
        _getMessageAttestationsStorage()[digest].executed = true;

        return false;
    }

    /// @dev Called after a message has been sufficiently verified to execute the command in the message.
    ///      This function will decode the payload as an ManagerMessage to extract the sequence, msgType, and other parameters.
    /// TODO: we could make this public. all the security checks are done here
    function _executeMsg(
        uint16 sourceChainId,
        bytes32 sourceManagerAddress,
        EndpointStructs.ManagerMessage memory message
    ) internal {
        // verify chain has not forked
        checkFork(evmChainId);

        bytes32 digest = EndpointStructs.managerMessageDigest(sourceChainId, message);

        if (!isMessageApproved(digest)) {
            revert MessageNotApproved(digest);
        }

        bool msgAlreadyExecuted = _replayProtect(digest);
        if (msgAlreadyExecuted) {
            // end execution early to mitigate the possibility of race conditions from endpoints
            // attempting to deliver the same message when (threshold < number of endpoint messages)
            // notify client (off-chain process) so they don't attempt redundant msg delivery
            emit MessageAlreadyExecuted(sourceManagerAddress, digest);
            return;
        }

        EndpointStructs.NativeTokenTransfer memory nativeTokenTransfer =
            EndpointStructs.parseNativeTokenTransfer(message.payload);

        // verify that the destination chain is valid
        if (nativeTokenTransfer.toChain != chainId) {
            revert InvalidTargetChain(nativeTokenTransfer.toChain, chainId);
        }

        NormalizedAmount memory nativeTransferAmount = nttFixDecimals(nativeTokenTransfer.amount);

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

        _mintOrUnlockToRecipient(transferRecipient, nativeTransferAmount);
    }

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
        _mintOrUnlockToRecipient(queuedTransfer.recipient, queuedTransfer.amount);
    }

    function _mintOrUnlockToRecipient(address recipient, NormalizedAmount memory amount) internal {
        // calculate proper amount of tokens to unlock/mint to recipient
        // denormalize the amount
        uint256 denormalizedAmount = nttDenormalize(amount);

        if (mode == Mode.LOCKING) {
            // unlock tokens to the specified recipient
            IERC20(token).safeTransfer(recipient, denormalizedAmount);
        } else if (mode == Mode.BURNING) {
            // mint tokens to the specified recipient
            INTTToken(token).mint(recipient, denormalizedAmount);
        } else {
            revert InvalidMode(uint8(mode));
        }
    }

    function nextMessageSequence() external view returns (uint64) {
        return _getMessageSequenceStorage().num;
    }

    function _useMessageSequence() internal returns (uint64 currentSequence) {
        currentSequence = _getMessageSequenceStorage().num;
        _getMessageSequenceStorage().num++;
    }

    function getTokenBalanceOf(
        address tokenAddr,
        address accountAddr
    ) internal view returns (uint256) {
        (, bytes memory queriedBalance) =
            tokenAddr.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, accountAddr));
        return abi.decode(queriedBalance, (uint256));
    }

    function isMessageExecuted(bytes32 digest) public view returns (bool) {
        return _getMessageAttestationsStorage()[digest].executed;
    }

    function getSibling(uint16 chainId_) public view returns (bytes32) {
        return _getSiblingsStorage()[chainId_];
    }

    function setSibling(uint16 siblingChainId, bytes32 siblingContract) public virtual onlyOwner {
        if (siblingChainId == 0) {
            revert InvalidSiblingChainIdZero();
        }
        if (siblingContract == bytes32(0)) {
            revert InvalidSiblingZeroAddress();
        }

        bytes32 oldSiblingContract = _getSiblingsStorage()[siblingChainId];

        _getSiblingsStorage()[siblingChainId] = siblingContract;

        emit SiblingUpdated(siblingChainId, oldSiblingContract, siblingContract);
    }

    function _tokenDecimals() internal view override returns (uint8) {
        return tokenDecimals;
    }
}

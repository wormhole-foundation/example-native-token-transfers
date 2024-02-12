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
import "./libraries/NormalizedAmount.sol";
import "./interfaces/IManager.sol";
import "./interfaces/IManagerEvents.sol";
import "./interfaces/IEndpointToken.sol";
import "./Endpoint.sol";
import "./EndpointRegistry.sol";

// TODO: rename this (it's really the business logic)
abstract contract Manager is
    IManager,
    IManagerEvents,
    EndpointRegistry,
    RateLimiter,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;
    using NormalizedAmountLib for uint256;
    using NormalizedAmountLib for NormalizedAmount;

    error RefundFailed(uint256 refundAmount);

    address public immutable token;
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
    ) RateLimiter(_rateLimitDuration) {
        token = _token;
        mode = _mode;
        chainId = _chainId;
        evmChainId = block.chainid;
    }

    function __Manager_init() internal onlyInitializing {
        // TODO: shouldn't be msg.sender but a separate (contract) address that's passed in the initializer
        __Ownable_init(msg.sender);
        // TODO: check if it's safe to not initialise reentrancy guard
        __ReentrancyGuard_init();
    }

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function quoteDeliveryPrice(uint16 recipientChain) public view virtual returns (uint256);

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function _sendMessageToEndpoint(
        uint16 recipientChain,
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
        uint8 decimals = _tokenDecimals();
        NormalizedAmount normalized = NormalizedAmountLib.normalize(limit, decimals);
        _setOutboundLimit(normalized);
    }

    function setInboundLimit(uint256 limit, uint16 chainId_) external onlyOwner {
        uint8 decimals = _tokenDecimals();
        NormalizedAmount normalized = NormalizedAmountLib.normalize(limit, decimals);
        _setInboundLimit(normalized, chainId_);
    }

    function completeOutboundQueuedTransfer(uint64 messageSequence)
        external
        payable
        nonReentrant
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
            queuedTransfer.sender
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
    function normalizeTransferAmount(uint256 amount) internal view returns (NormalizedAmount) {
        NormalizedAmount normalizedAmount;
        {
            // query tokens decimals
            uint8 decimals = _tokenDecimals();

            normalizedAmount = amount.normalize(decimals);
            // don't deposit dust that can not be bridged due to the decimal shift
            uint256 newAmount = normalizedAmount.denormalize(decimals);
            if (amount != newAmount) {
                revert TransferAmountHasDust(amount, amount - newAmount);
            }
        }

        return normalizedAmount;
    }

    /// @notice Called by the user to send the token cross-chain.
    ///         This function will either lock or burn the sender's tokens.
    ///         Finally, this function will call into the Endpoint contracts to send a message with the incrementing sequence number, msgType = 1y, and the token transfer payload.
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bool shouldQueue
    ) external payable nonReentrant returns (uint64 msgSequence) {
        if (amount == 0) {
            revert ZeroAmount();
        }

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
        NormalizedAmount normalizedAmount = normalizeTransferAmount(amount);

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
                    sequence, normalizedAmount, recipientChain, recipient, msg.sender
                );

                // refund price quote back to sender
                refundToSender(msg.value);

                // return the sequence in the queue
                return sequence;
            }
        }

        // otherwise, consume the outbound amount
        _consumeOutboundAmount(normalizedAmount);

        return _transfer(sequence, normalizedAmount, recipientChain, recipient, msg.sender);
    }

    function _transfer(
        uint64 sequence,
        NormalizedAmount amount,
        uint16 recipientChain,
        bytes32 recipient,
        address sender
    ) internal returns (uint64 msgSequence) {
        {
            // check up front that msg.value will cover the delivery price
            uint256 totalPriceQuote = quoteDeliveryPrice(recipientChain);
            if (msg.value < totalPriceQuote) {
                revert DeliveryPaymentTooLow(totalPriceQuote, msg.value);
            }

            // refund user extra excess value from msg.value
            uint256 excessValue = totalPriceQuote - msg.value;
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
                chainId,
                sequence,
                toWormholeFormat(address(this)),
                toWormholeFormat(sender),
                encodedTransferPayload
            )
        );

        // send the message
        _sendMessageToEndpoint(recipientChain, encodedManagerPayload);

        emit TransferSent(recipient, amount.denormalize(_tokenDecimals()), recipientChain, sequence);

        // return the sequence number
        return sequence;
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
    function _executeMsg(EndpointStructs.ManagerMessage memory message) internal {
        // verify chain has not forked
        checkFork(evmChainId);

        // verify message came from a sibling manager contract
        if (getSibling(message.chainId) != message.sourceManager) {
            revert InvalidSibling(message.chainId, message.sourceManager);
        }

        bytes32 digest = EndpointStructs.managerMessageDigest(message);

        if (!isMessageApproved(digest)) {
            revert MessageNotApproved(digest);
        }

        bool msgAlreadyExecuted = _replayProtect(digest);
        if (msgAlreadyExecuted) {
            // end execution early to mitigate the possibility of race conditions from endpoints
            // attempting to deliver the same message when (threshold < number of endpoint messages)
            // notify client (off-chain process) so they don't attempt redundant msg delivery
            emit MessageAlreadyExecuted(message.sourceManager, digest);
            return;
        }

        EndpointStructs.NativeTokenTransfer memory nativeTokenTransfer =
            EndpointStructs.parseNativeTokenTransfer(message.payload);

        // verify that the destination chain is valid
        if (nativeTokenTransfer.toChain != chainId) {
            revert InvalidTargetChain(nativeTokenTransfer.toChain, chainId);
        }

        NormalizedAmount nativeTransferAmount = nativeTokenTransfer.amount;

        address transferRecipient = fromWormholeFormat(nativeTokenTransfer.to);

        {
            // Check inbound rate limits
            bool isRateLimited = _isInboundAmountRateLimited(nativeTransferAmount, message.chainId);
            if (isRateLimited) {
                // queue up the transfer
                _enqueueInboundTransfer(digest, nativeTransferAmount, transferRecipient);

                // end execution early
                return;
            }
        }

        // consume the amount for the inbound rate limit
        _consumeInboundAmount(nativeTransferAmount, message.chainId);

        _mintOrUnlockToRecipient(transferRecipient, nativeTransferAmount);
    }

    function completeInboundQueuedTransfer(bytes32 digest) external nonReentrant {
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

    function _mintOrUnlockToRecipient(address recipient, NormalizedAmount amount) internal {
        // calculate proper amount of tokens to unlock/mint to recipient
        // query the decimals of the token contract that's tied to this manager
        // adjust the decimals of the amount in the nativeTokenTransfer payload accordingly
        uint8 decimals = _tokenDecimals();
        uint256 denormalizedAmount = amount.denormalize(decimals);

        if (mode == Mode.LOCKING) {
            // unlock tokens to the specified recipient
            IERC20(token).safeTransfer(recipient, denormalizedAmount);
        } else if (mode == Mode.BURNING) {
            // mint tokens to the specified recipient
            IEndpointToken(token).mint(recipient, denormalizedAmount);
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
        (, bytes memory queriedDecimals) = token.staticcall(abi.encodeWithSignature("decimals()"));
        return abi.decode(queriedDecimals, (uint8));
    }
}

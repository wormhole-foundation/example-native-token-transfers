// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "./libraries/external/OwnableUpgradeable.sol";
import "./libraries/external/ReentrancyGuardUpgradeable.sol";
import "./libraries/EndpointStructs.sol";
import "./libraries/EndpointHelpers.sol";
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
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;

    address public immutable token;
    Mode public immutable mode;
    uint16 public immutable chainId;
    uint256 public immutable evmChainId;

    /**
     * @dev The duration it takes for the limits to fully replenish
     */
    uint256 public immutable rateLimitDuration;

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

    bytes32 public constant OUTBOUND_LIMIT_PARAMS_SLOT =
        bytes32(uint256(keccak256("ntt.outboundLimitParams")) - 1);

    bytes32 public constant OUTBOUND_QUEUE_SLOT =
        bytes32(uint256(keccak256("ntt.outboundQueue")) - 1);

    bytes32 public constant INBOUND_LIMIT_PARAMS_SLOT =
        bytes32(uint256(keccak256("ntt.inboundLimitParams")) - 1);

    bytes32 public constant INBOUND_QUEUE_SLOT = bytes32(uint256(keccak256("ntt.inboundQueue")) - 1);

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

    function _getSiblingsStorage() internal pure returns (mapping(uint16 => bytes) storage $) {
        uint256 slot = uint256(SIBLINGS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

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

    constructor(address _token, Mode _mode, uint16 _chainId, uint256 _rateLimitDuration) {
        token = _token;
        mode = _mode;
        chainId = _chainId;
        evmChainId = block.chainid;
        rateLimitDuration = _rateLimitDuration;
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
    function _sendMessageToEndpoint(uint16 recipientChain, bytes memory payload) internal virtual;

    // TODO: do we want additional information (like chain etc)
    function isMessageApproved(bytes32 digest) public view virtual returns (bool);

    function _setEndpointAttestedToMessage(bytes32 digest, uint8 index) internal {
        _getMessageAttestationsStorage()[digest].attestedEndpoints |= uint64(1 << index);
    }

    function _setEndpointAttestedToMessage(bytes32 digest, address endpoint) internal {
        _setEndpointAttestedToMessage(digest, _getEndpointInfosStorage()[endpoint].index);
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

    function _setLimit(uint256 limit, RateLimitParams storage rateLimitParams) internal {
        uint256 oldLimit = rateLimitParams.limit;
        uint256 currentCapacity = _getCurrentCapacity(rateLimitParams);
        rateLimitParams.limit = limit;

        rateLimitParams.currentCapacity =
            _calculateNewCurrentCapacity(limit, oldLimit, currentCapacity);

        rateLimitParams.ratePerSecond = limit / rateLimitDuration;
        rateLimitParams.lastTxTimestamp = block.timestamp;
    }

    function setOutboundLimit(uint256 limit) external onlyOwner {
        _setLimit(limit, _getOutboundLimitParamsStorage());
    }

    function getOutboundLimitParams() public pure returns (RateLimitParams memory) {
        return _getOutboundLimitParamsStorage();
    }

    function getCurrentOutboundCapacity() public view returns (uint256) {
        return _getCurrentCapacity(getOutboundLimitParams());
    }

    function getOutboundQueuedTransfer(uint64 queueSequence)
        public
        view
        returns (OutboundQueuedTransfer memory)
    {
        return _getOutboundQueueStorage()[queueSequence];
    }

    function setInboundLimit(uint256 limit, uint16 chainId_) external onlyOwner {
        _setLimit(limit, _getInboundLimitParamsStorage()[chainId_]);
    }

    function getInboundLimitParams(uint16 chainId_) public view returns (RateLimitParams memory) {
        return _getInboundLimitParamsStorage()[chainId_];
    }

    function getCurrentInboundCapacity(uint16 chainId_) public view returns (uint256) {
        return _getCurrentCapacity(getInboundLimitParams(chainId_));
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
        returns (uint256 capacity)
    {
        uint256 timePassed = block.timestamp - rateLimitParams.lastTxTimestamp;
        uint256 calculatedCapacity =
            rateLimitParams.currentCapacity + (timePassed * rateLimitParams.ratePerSecond);

        return min(calculatedCapacity, rateLimitParams.limit);
    }

    /**
     * @dev Updates the current capacity
     *
     * @param newLimit The new limit
     * @param oldLimit The old limit
     * @param currentCapacity The current capacity
     */
    function _calculateNewCurrentCapacity(
        uint256 newLimit,
        uint256 oldLimit,
        uint256 currentCapacity
    ) internal pure returns (uint256 newCurrentCapacity) {
        uint256 difference;

        if (oldLimit > newLimit) {
            difference = oldLimit - newLimit;
            newCurrentCapacity = currentCapacity > difference ? currentCapacity - difference : 0;
        } else {
            difference = newLimit - oldLimit;
            newCurrentCapacity = currentCapacity + difference;
        }
    }

    function _consumeOutboundAmount(uint256 amount) internal {
        _consumeRateLimitAmount(
            amount, getCurrentOutboundCapacity(), _getOutboundLimitParamsStorage()
        );
    }

    function _consumeInboundAmount(uint256 amount, uint16 chainId_) internal {
        _consumeRateLimitAmount(
            amount, getCurrentInboundCapacity(chainId_), _getInboundLimitParamsStorage()[chainId_]
        );
    }

    function _consumeRateLimitAmount(
        uint256 amount,
        uint256 capacity,
        RateLimitParams storage rateLimitParams
    ) internal {
        rateLimitParams.lastTxTimestamp = block.timestamp;
        rateLimitParams.currentCapacity = capacity - amount;
    }

    function _isOutboundAmountRateLimited(uint256 amount) internal view returns (bool) {
        return _isAmountRateLimited(getCurrentOutboundCapacity(), amount);
    }

    function _isInboundAmountRateLimited(
        uint256 amount,
        uint16 chainId_
    ) internal view returns (bool) {
        return _isAmountRateLimited(getCurrentInboundCapacity(chainId_), amount);
    }

    function _isAmountRateLimited(uint256 capacity, uint256 amount) internal pure returns (bool) {
        if (capacity < amount) {
            return true;
        }
        return false;
    }

    function _enqueueOutboundTransfer(
        uint64 sequence,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) internal {
        _getOutboundQueueStorage()[sequence] = OutboundQueuedTransfer({
            amount: amount,
            recipientChain: recipientChain,
            recipient: recipient,
            txTimestamp: block.timestamp
        });
    }

    function _enqueueInboundTransfer(bytes32 digest, uint256 amount, address recipient) internal {
        _getInboundQueueStorage()[digest] = InboundQueuedTransfer({
            amount: amount,
            recipient: recipient,
            txTimestamp: block.timestamp
        });

        emit InboundTransferQueued(digest);
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
            queuedTransfer.recipient
        );
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
        // query tokens decimals
        (, bytes memory queriedDecimals) = token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // don't deposit dust that can not be bridged due to the decimal shift
        uint256 newAmount = deNormalizeAmount(normalizeAmount(amount, decimals), decimals);
        if (amount != newAmount) {
            revert TransferAmountHasDust(amount, amount - newAmount);
        }

        if (amount == 0) {
            revert ZeroAmount();
        }

        // Lock/burn tokens before checking rate limits
        if (mode == Mode.LOCKING) {
            // use transferFrom to pull tokens from the user and lock them
            // query own token balance before transfer
            uint256 balanceBefore = getTokenBalanceOf(token, address(this));

            // transfer tokens
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

            // query own token balance after transfer
            uint256 balanceAfter = getTokenBalanceOf(token, address(this));

            // correct amount for potential transfer fees
            amount = balanceAfter - balanceBefore;
        } else if (mode == Mode.BURNING) {
            // query sender's token balance before transfer
            uint256 balanceBefore = getTokenBalanceOf(token, msg.sender);

            // call the token's burn function to burn the sender's token
            ERC20Burnable(token).burnFrom(msg.sender, amount);

            // query sender's token balance after transfer
            uint256 balanceAfter = getTokenBalanceOf(token, msg.sender);

            // correct amount for potential burn fees
            amount = balanceAfter - balanceBefore;
        } else {
            revert InvalidMode(uint8(mode));
        }

        // get the sequence for this transfer
        uint64 sequence = _useMessageSequence();

        // now check rate limits
        bool isAmountRateLimited = _isOutboundAmountRateLimited(amount);
        if (!shouldQueue && isAmountRateLimited) {
            revert NotEnoughCapacity(getCurrentOutboundCapacity(), amount);
        }
        if (shouldQueue && isAmountRateLimited) {
            // queue up and return
            _enqueueOutboundTransfer(sequence, amount, recipientChain, recipient);

            // refund the price quote back to sender
            payable(msg.sender).transfer(msg.value);

            // return the sequence in the queue
            return sequence;
        }

        // otherwise, consume the outbound amount
        _consumeOutboundAmount(amount);

        return _transfer(sequence, amount, recipientChain, recipient);
    }

    function _transfer(
        uint64 sequence,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) internal returns (uint64 msgSequence) {
        // check up front that msg.value will cover the delivery price
        uint256 totalPriceQuote = quoteDeliveryPrice(recipientChain);
        if (msg.value < totalPriceQuote) {
            revert DeliveryPaymentTooLow(totalPriceQuote, msg.value);
        }

        // refund user extra excess value from msg.value
        uint256 excessValue = totalPriceQuote - msg.value;
        if (excessValue > 0) {
            payable(msg.sender).transfer(excessValue);
        }

        // query tokens decimals
        (, bytes memory queriedDecimals) = token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // normalize amount decimals
        uint256 normalizedAmount = normalizeAmount(amount, decimals);

        bytes memory sourceTokenBytes = abi.encodePacked(token);
        bytes memory recipientBytes = abi.encodePacked(recipient);
        bytes memory encodedTransferPayload = EndpointStructs.encodeNativeTokenTransfer(
            EndpointStructs.NativeTokenTransfer(
                normalizedAmount, sourceTokenBytes, recipientBytes, recipientChain
            )
        );

        // construct the ManagerMessage payload
        bytes memory sourceManagerBytes = abi.encodePacked(address(this));
        bytes memory senderBytes = abi.encodePacked(msg.sender);
        bytes memory encodedManagerPayload = EndpointStructs.encodeManagerMessage(
            EndpointStructs.ManagerMessage(
                chainId, sequence, sourceManagerBytes, senderBytes, encodedTransferPayload
            )
        );

        // send the message
        _sendMessageToEndpoint(recipientChain, encodedManagerPayload);

        // return the sequence number
        return sequence;
    }

    function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals > 8) {
            amount /= 10 ** (decimals - 8);
        }
        return amount;
    }

    function deNormalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals > 8) {
            amount *= 10 ** (decimals - 8);
        }
        return amount;
    }

    // @dev Mark a message as executed.
    // This function will revert if the message has already been executed.
    function _replayProtect(bytes32 digest) internal {
        // check if this message has already been executed
        if (isMessageExecuted(digest)) {
            revert MessageAlreadyExecuted(digest);
        }

        // mark this message as executed
        _getMessageAttestationsStorage()[digest].executed = true;
    }

    /// @dev Called after a message has been sufficiently verified to execute the command in the message.
    ///      This function will decode the payload as an ManagerMessage to extract the sequence, msgType, and other parameters.
    /// TODO: we could make this public. all the security checks are done here
    function _executeMsg(EndpointStructs.ManagerMessage memory message) internal {
        // verify chain has not forked
        checkFork(evmChainId);

        // verify message came from a sibling manager contract
        if (!_areBytesEqual(getSibling(message.chainId), message.sourceManager)) {
            revert InvalidSibling(message.chainId, message.sourceManager);
        }

        bytes32 digest = EndpointStructs.managerMessageDigest(message);

        if (!isMessageApproved(digest)) {
            revert MessageNotApproved(digest);
        }

        _replayProtect(digest);

        EndpointStructs.NativeTokenTransfer memory nativeTokenTransfer =
            EndpointStructs.parseNativeTokenTransfer(message.payload);

        // verify that the destination chain is valid
        if (nativeTokenTransfer.toChain != chainId) {
            revert InvalidTargetChain(nativeTokenTransfer.toChain, chainId);
        }

        // calculate proper amount of tokens to unlock/mint to recipient
        // query the decimals of the token contract that's tied to this manager
        // adjust the decimals of the amount in the nativeTokenTransfer payload accordingly
        (, bytes memory queriedDecimals) = token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        uint256 nativeTransferAmount = deNormalizeAmount(nativeTokenTransfer.amount, decimals);

        address transferRecipient = bytesToAddress(nativeTokenTransfer.to);

        // Check inbound rate limits
        bool isRateLimited = _isInboundAmountRateLimited(nativeTransferAmount, message.chainId);
        if (isRateLimited) {
            // queue up the transfer
            _enqueueInboundTransfer(digest, nativeTransferAmount, transferRecipient);

            // end execution early
            return;
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

    function _mintOrUnlockToRecipient(address recipient, uint256 amount) internal {
        if (mode == Mode.LOCKING) {
            // unlock tokens to the specified recipient
            IERC20(token).safeTransfer(recipient, amount);
        } else if (mode == Mode.BURNING) {
            // mint tokens to the specified recipient
            IEndpointToken(token).mint(recipient, amount);
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

    function bytesToAddress(bytes memory b) public pure returns (address) {
        (address addr, uint256 offset) = b.asAddress(0);
        b.checkLength(offset);
        return addr;
    }

    function isMessageExecuted(bytes32 digest) public view returns (bool) {
        return _getMessageAttestationsStorage()[digest].executed;
    }

    function getSibling(uint16 chainId_) public view returns (bytes memory) {
        return _getSiblingsStorage()[chainId_];
    }

    function setSibling(uint16 chainId_, bytes memory siblingContract) external onlyOwner {
        if (chainId_ == 0) {
            revert InvalidSiblingChainIdZero();
        }
        if (siblingContract.length == 0) {
            revert InvalidSiblingZeroLength();
        }
        if (_isAllZeros(siblingContract)) {
            revert InvalidSiblingZeroBytes();
        }
        _getSiblingsStorage()[chainId_] = siblingContract;
    }

    function _isAllZeros(bytes memory payload) internal pure returns (bool) {
        for (uint256 i = 0; i < payload.length; i++) {
            if (payload[i] != 0) {
                return false;
            }
        }
        return true;
    }

    function _areBytesEqual(bytes memory a, bytes memory b) internal pure returns (bool) {
        if (a.length != b.length) {
            return false;
        }

        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }

        return true;
    }
}

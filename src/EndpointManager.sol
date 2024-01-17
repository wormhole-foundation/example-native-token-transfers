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
import "./interfaces/IEndpointManager.sol";
import "./interfaces/IEndpointToken.sol";
import "./Endpoint.sol";
import "./EndpointRegistry.sol";

// TODO: rename this (it's really the business logic)
abstract contract EndpointManager is
    IEndpointManager,
    EndpointRegistry,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;

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

    struct _QueueSequence {
        uint64 num;
    }

    /// =============== STORAGE ===============================================

    bytes32 public constant MESSAGE_ATTESTATIONS_SLOT =
        bytes32(uint256(keccak256("ntt.messageAttestations")) - 1);

    bytes32 public constant SEQUENCE_SLOT = bytes32(uint256(keccak256("ntt.sequence")) - 1);

    bytes32 public constant OUTBOUND_LIMIT_PARAMS_SLOT =
        bytes32(uint256(keccak256("ntt.outboundLimitParams")) - 1);

    bytes32 public constant OUTBOUND_QUEUE_SLOT =
        bytes32(uint256(keccak256("ntt.outboundQueue")) - 1);

    bytes32 public constant OUTBOUND_QUEUE_SEQUENCE_SLOT =
        bytes32(uint256(keccak256("ntt.outboundQueueSequence")) - 1);

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

    function _getSequenceStorage() internal pure returns (_Sequence storage $) {
        uint256 slot = uint256(SEQUENCE_SLOT);
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

    function _getOutboundQueueSequenceStorage() internal pure returns (_QueueSequence storage $) {
        uint256 slot = uint256(OUTBOUND_QUEUE_SEQUENCE_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    address immutable _token;
    Mode immutable _mode;
    uint16 immutable _chainId;
    uint256 immutable _evmChainId;

    /**
     * @dev The duration it takes for the limits to fully replenish
     */
    uint256 public immutable _rateLimitDuration;

    constructor(address tokenAddress, Mode mode, uint16 chainId, uint256 rateLimitDuration) {
        _token = tokenAddress;
        _mode = mode;
        _chainId = chainId;
        _evmChainId = block.chainid;
        _rateLimitDuration = rateLimitDuration;
    }

    function initialize() public initializer {
        // TODO: shouldn't be msg.sender but a separate (contract) address that's passed in the initializer
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
    }

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function quoteDeliveryPrice(uint16 recipientChain) public view virtual returns (uint256);

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function sendMessage(uint16 recipientChain, bytes memory payload) internal virtual;

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function setSibling(uint16 siblingChainId, bytes32 siblingContract) external virtual;

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

    function setOutboundLimit(uint256 limit) external onlyOwner {
        uint256 oldLimit = _getOutboundLimitParamsStorage().limit;
        uint256 currentCapacity = getCurrentOutboundCapacity();
        _getOutboundLimitParamsStorage().limit = limit;

        _getOutboundLimitParamsStorage().currentCapacity =
            _calculateNewCurrentCapacity(limit, oldLimit, currentCapacity);

        _getOutboundLimitParamsStorage().ratePerSecond = limit / _rateLimitDuration;
        _getOutboundLimitParamsStorage().lastTxTimestamp = block.timestamp;
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

    /**
     * @dev Gets the current capacity for a parameterized rate limits struct
     */
    function _getCurrentCapacity(RateLimitParams memory rateLimitParams)
        internal
        view
        returns (uint256 capacity)
    {
        capacity = rateLimitParams.currentCapacity;
        if (capacity == rateLimitParams.limit) {
            return capacity;
        } else if (rateLimitParams.lastTxTimestamp + _rateLimitDuration <= block.timestamp) {
            capacity = rateLimitParams.limit;
        } else if (rateLimitParams.lastTxTimestamp + _rateLimitDuration > block.timestamp) {
            uint256 timePassed = block.timestamp - rateLimitParams.lastTxTimestamp;
            uint256 calculatedCapacity = capacity + (timePassed * rateLimitParams.ratePerSecond);
            capacity = calculatedCapacity > rateLimitParams.limit
                ? rateLimitParams.limit
                : calculatedCapacity;
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

    function _consumeOutboundAmount(uint256 amount) internal returns (bool didConsume) {
        uint256 currentCapacity = getCurrentOutboundCapacity();
        if (currentCapacity < amount) {
            return false;
        }
        _getOutboundLimitParamsStorage().lastTxTimestamp = block.timestamp;
        _getOutboundLimitParamsStorage().currentCapacity = currentCapacity - amount;
        return true;
    }

    function completeOutboundQueuedTransfer(uint64 queueSequence)
        external
        payable
        nonReentrant
        returns (uint64 msgSequence)
    {
        // find the message in the queue
        OutboundQueuedTransfer memory queuedTransfer = _getOutboundQueueStorage()[queueSequence];
        if (!queuedTransfer.isSet) {
            revert OutboundQueuedTransferNotFound(queueSequence);
        }

        // check that > RATE_LIMIT_DURATION has elapsed
        if (block.timestamp - queuedTransfer.txTimestamp < _rateLimitDuration) {
            revert OutboundQueuedTransferStillQueued(queuedTransfer.txTimestamp);
        }

        // remove transfer from the queue
        delete _getOutboundQueueStorage()[queueSequence];

        // run it through the transfer logic and skip the rate limit
        return _transfer(
            queuedTransfer.amount,
            queuedTransfer.recipientChain,
            queuedTransfer.recipient,
            true,
            false
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
        return _transfer(amount, recipientChain, recipient, false, shouldQueue);
    }

    function _transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bool shouldSkipRateLimit,
        bool shouldQueue
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
        (, bytes memory queriedDecimals) = _token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // don't deposit dust that can not be bridged due to the decimal shift
        amount = deNormalizeAmount(normalizeAmount(amount, decimals), decimals);

        if (amount == 0) {
            revert ZeroAmount();
        }

        if (!shouldSkipRateLimit) {
            bool didConsumeAmount = _consumeOutboundAmount(amount);
            if (shouldQueue && !didConsumeAmount) {
                // queue up and return
                uint64 queueSequence = useOutboundQueueSequence();

                _getOutboundQueueStorage()[queueSequence] = OutboundQueuedTransfer({
                    amount: amount,
                    recipientChain: recipientChain,
                    recipient: recipient,
                    txTimestamp: block.timestamp,
                    isSet: true
                });

                // refund the price quote back to sender
                payable(msg.sender).transfer(totalPriceQuote);

                // return the sequence in the queue
                return queueSequence;
            } else if (!didConsumeAmount) {
                revert NotEnoughOutboundCapacity(getCurrentOutboundCapacity(), amount);
            }
        }

        if (_mode == Mode.LOCKING) {
            // use transferFrom to pull tokens from the user and lock them
            // query own token balance before transfer
            uint256 balanceBefore = getTokenBalanceOf(_token, address(this));

            // transfer tokens
            IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);

            // query own token balance after transfer
            uint256 balanceAfter = getTokenBalanceOf(_token, address(this));

            // correct amount for potential transfer fees
            amount = balanceAfter - balanceBefore;
        } else {
            // query sender's token balance before transfer
            uint256 balanceBefore = getTokenBalanceOf(_token, msg.sender);

            // call the token's burn function to burn the sender's token
            ERC20Burnable(_token).burnFrom(msg.sender, amount);

            // query sender's token balance after transfer
            uint256 balanceAfter = getTokenBalanceOf(_token, msg.sender);

            // correct amount for potential burn fees
            amount = balanceAfter - balanceBefore;
        }

        // normalize amount decimals
        uint256 normalizedAmount = normalizeAmount(amount, decimals);

        bytes memory recipientBytes = abi.encodePacked(recipient);

        EndpointStructs.NativeTokenTransfer memory nativeTokenTransfer = EndpointStructs
            .NativeTokenTransfer({amount: normalizedAmount, to: recipientBytes, toChain: recipientChain});

        bytes memory encodedTransferPayload =
            EndpointStructs.encodeNativeTokenTransfer(nativeTokenTransfer);

        // construct the ManagerMessage payload
        uint64 sequence = useSequence();
        bytes memory encodedManagerPayload = EndpointStructs.encodeEndpointManagerMessage(
            EndpointStructs.EndpointManagerMessage(_chainId, sequence, 1, encodedTransferPayload)
        );

        // send the message
        sendMessage(recipientChain, encodedManagerPayload);

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
    ///      This function will decode the payload as an EndpointManagerMessage to extract the sequence, msgType, and other parameters.
    /// TODO: we could make this public. all the security checks are done here
    function _executeMsg(EndpointStructs.EndpointManagerMessage memory message) internal {
        // verify chain has not forked
        checkFork(_evmChainId);

        bytes32 digest = EndpointStructs.endpointManagerMessageDigest(message);

        if (!isMessageApproved(digest)) {
            revert MessageNotApproved(digest);
        }

        _replayProtect(digest);

        // for msgType == 1, parse the payload as a NativeTokenTransfer.
        // for other msgTypes, revert (unsupported for now)
        if (message.msgType != 1) {
            revert UnexpectedEndpointManagerMessageType(message.msgType);
        }
        EndpointStructs.NativeTokenTransfer memory nativeTokenTransfer =
            EndpointStructs.parseNativeTokenTransfer(message.payload);

        // verify that the destination chain is valid
        if (nativeTokenTransfer.toChain != _chainId) {
            revert InvalidTargetChain(nativeTokenTransfer.toChain, _chainId);
        }

        // calculate proper amount of tokens to unlock/mint to recipient
        // query the decimals of the token contract that's tied to this manager
        // adjust the decimals of the amount in the nativeTokenTransfer payload accordingly
        (, bytes memory queriedDecimals) = _token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        uint256 nativeTransferAmount = deNormalizeAmount(nativeTokenTransfer.amount, decimals);

        address transferRecipient = bytesToAddress(nativeTokenTransfer.to);

        if (_mode == Mode.LOCKING) {
            // unlock tokens to the specified recipient
            IERC20(_token).safeTransfer(transferRecipient, nativeTransferAmount);
        } else {
            // mint tokens to the specified recipient
            IEndpointToken(_token).mint(transferRecipient, nativeTransferAmount);
        }
    }

    function nextSequence() public view returns (uint64) {
        return _getSequenceStorage().num;
    }

    function useSequence() internal returns (uint64 currentSequence) {
        currentSequence = nextSequence();
        incrementSequence();
    }

    function incrementSequence() internal {
        _getSequenceStorage().num++;
    }

    function nextOutboundQueueSequence() public view returns (uint64) {
        return _getOutboundQueueSequenceStorage().num;
    }

    function useOutboundQueueSequence() internal returns (uint64 currentSequence) {
        currentSequence = nextOutboundQueueSequence();
        incrementOutboundQueueSequence();
    }

    function incrementOutboundQueueSequence() internal {
        _getOutboundQueueSequenceStorage().num++;
    }

    function getTokenBalanceOf(
        address tokenAddr,
        address accountAddr
    ) internal view returns (uint256) {
        (, bytes memory queriedBalance) =
            tokenAddr.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, accountAddr));
        return abi.decode(queriedBalance, (uint256));
    }

    function token() external view override returns (address) {
        return _token;
    }

    function bytesToAddress(bytes memory b) public pure returns (address) {
        (address addr, uint256 offset) = b.asAddress(0);
        b.checkLength(offset);
        return addr;
    }

    function isMessageExecuted(bytes32 digest) public view returns (bool) {
        return _getMessageAttestationsStorage()[digest].executed;
    }
}

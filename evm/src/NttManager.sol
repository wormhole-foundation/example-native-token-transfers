// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "./libraries/external/OwnableUpgradeable.sol";
import "./libraries/external/ReentrancyGuardUpgradeable.sol";
import "./libraries/TransceiverStructs.sol";
import "./libraries/TransceiverHelpers.sol";
import "./libraries/RateLimiter.sol";
import "./interfaces/INttManager.sol";
import "./interfaces/INttManagerEvents.sol";
import "./interfaces/INTTToken.sol";
import "./interfaces/ITransceiver.sol";
import "./TransceiverRegistry.sol";
import "./NttNormalizer.sol";
import "./libraries/PausableOwnable.sol";
import "./libraries/Implementation.sol";

contract NttManager is
    INttManager,
    INttManagerEvents,
    TransceiverRegistry,
    RateLimiter,
    NttNormalizer,
    ReentrancyGuardUpgradeable,
    PausableOwnable,
    Implementation
{
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;

    error RefundFailed(uint256 refundAmount);
    error CannotRenounceNttManagerOwnership(address owner);
    error UnexpectedOwner(address expectedOwner, address owner);
    error TransceiverAlreadyAttestedToMessage(bytes32 nttManagerMessageHash);

    address public immutable token;
    address immutable deployer;
    Mode public immutable mode;
    uint16 public immutable chainId;
    uint256 immutable evmChainId;

    enum Mode {
        LOCKING,
        BURNING
    }

    // @dev Information about attestations for a given message.
    struct AttestationInfo {
        // whether this message has been executed
        bool executed;
        // bitmap of transceivers that have attested to this message (NOTE: might contain disabled transceivers)
        uint64 attestedTransceivers;
    }

    struct _Sequence {
        uint64 num;
    }

    struct _Threshold {
        uint8 num;
    }

    /// =============== STORAGE ===============================================

    bytes32 private constant MESSAGE_ATTESTATIONS_SLOT =
        bytes32(uint256(keccak256("ntt.messageAttestations")) - 1);

    bytes32 private constant MESSAGE_SEQUENCE_SLOT =
        bytes32(uint256(keccak256("ntt.messageSequence")) - 1);

    bytes32 private constant PEERS_SLOT = bytes32(uint256(keccak256("ntt.peers")) - 1);

    bytes32 private constant THRESHOLD_SLOT = bytes32(uint256(keccak256("ntt.threshold")) - 1);

    /// =============== GETTERS/SETTERS ========================================

    function _getThresholdStorage() private pure returns (_Threshold storage $) {
        uint256 slot = uint256(THRESHOLD_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

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

    function _getPeersStorage() internal pure returns (mapping(uint16 => bytes32) storage $) {
        uint256 slot = uint256(PEERS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function setThreshold(uint8 threshold) external onlyOwner {
        if (threshold == 0) {
            revert ZeroThreshold();
        }

        _Threshold storage _threshold = _getThresholdStorage();
        uint8 oldThreshold = _threshold.num;

        _threshold.num = threshold;
        _checkThresholdInvariants();

        emit ThresholdChanged(oldThreshold, threshold);
    }

    function getMode() public view returns (uint8) {
        return uint8(mode);
    }

    /// @notice Returns the number of Transceivers that must attest to a msgId for
    ///         it to be considered valid and acted upon.
    function getThreshold() public view returns (uint8) {
        return _getThresholdStorage().num;
    }

    function setTransceiver(address transceiver) external onlyOwner {
        _setTransceiver(transceiver);

        _Threshold storage _threshold = _getThresholdStorage();
        // We do not automatically increase the threshold here.
        // Automatically increasing the threshold can result in a scenario
        // where in-flight messages can't be redeemed.
        // For example: Assume there is 1 Transceiver and the threshold is 1.
        // If we were to add a new Transceiver, the threshold would increase to 2.
        // However, all messages that are either in-flight or that are sent on
        // a source chain that does not yet have 2 Transceivers will only have been
        // sent from a single transceiver, so they would never be able to get
        // redeemed.
        // Instead, we leave it up to the owner to manually update the threshold
        // after some period of time, ideally once all chains have the new Transceiver
        // and transfers that were sent via the old configuration are all complete.
        // However if the threshold is 0 (the initial case) we do increment to 1.
        if (_threshold.num == 0) {
            _threshold.num = 1;
        }

        emit TransceiverAdded(transceiver, _getNumTransceiversStorage().enabled, _threshold.num);
    }

    function removeTransceiver(address transceiver) external onlyOwner {
        _removeTransceiver(transceiver);

        _Threshold storage _threshold = _getThresholdStorage();
        uint8 numEnabledTransceivers = _getNumTransceiversStorage().enabled;

        if (numEnabledTransceivers < _threshold.num) {
            _threshold.num = numEnabledTransceivers;
        }

        emit TransceiverRemoved(transceiver, _threshold.num);
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
        // save the deployer (check this on initialization)
        deployer = msg.sender;
    }

    function __NttManager_init() internal onlyInitializing {
        // check if the owner is the deployer of this contract
        if (msg.sender != deployer) {
            revert UnexpectedOwner(deployer, msg.sender);
        }
        __PausedOwnable_init(msg.sender, msg.sender);
        __ReentrancyGuard_init();
    }

    function _initialize() internal virtual override {
        __NttManager_init();
        _checkThresholdInvariants();
        _checkTransceiversInvariants();
    }

    function _migrate() internal virtual override {
        _checkThresholdInvariants();
        _checkTransceiversInvariants();
    }

    /// =============== ADMIN ===============================================
    function upgrade(address newImplementation) external onlyOwner {
        _upgrade(newImplementation);
    }

    /// @dev Transfer ownership of the NttManager contract and all Transceiver contracts to a new owner.
    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
        // loop through all the registered transceivers and set the new owner of each transceiver to the newOwner
        address[] storage _registeredTransceivers = _getRegisteredTransceiversStorage();
        _checkRegisteredTransceiversInvariants();

        for (uint256 i = 0; i < _registeredTransceivers.length; i++) {
            ITransceiver(_registeredTransceivers[i]).transferTransceiverOwnership(newOwner);
        }
    }

    /// @dev This method should return an array of delivery prices corresponding to each transceiver.
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

    function _sendMessageToTransceivers(
        uint16 recipientChain,
        uint256[] memory priceQuotes,
        TransceiverStructs.TransceiverInstruction[] memory transceiverInstructions,
        address[] memory enabledTransceivers,
        bytes memory nttManagerMessage
    ) internal {
        uint256 numEnabledTransceivers = enabledTransceivers.length;
        mapping(address => TransceiverInfo) storage transceiverInfos = _getTransceiverInfosStorage();
        // call into transceiver contracts to send the message
        for (uint256 i = 0; i < numEnabledTransceivers; i++) {
            address transceiverAddr = enabledTransceivers[i];
            // send it to the recipient nttManager based on the chain
            ITransceiver(transceiverAddr).sendMessage{value: priceQuotes[i]}(
                recipientChain,
                transceiverInstructions[transceiverInfos[transceiverAddr].index],
                nttManagerMessage,
                getPeer(recipientChain)
            );
        }
    }

    function isMessageApproved(bytes32 digest) public view returns (bool) {
        uint8 threshold = getThreshold();
        return messageAttestations(digest) >= threshold && threshold > 0;
    }

    function _setTransceiverAttestedToMessage(bytes32 digest, uint8 index) internal {
        _getMessageAttestationsStorage()[digest].attestedTransceivers |= uint64(1 << index);
    }

    function _setTransceiverAttestedToMessage(bytes32 digest, address transceiver) internal {
        _setTransceiverAttestedToMessage(digest, _getTransceiverInfosStorage()[transceiver].index);

        emit MessageAttestedTo(
            digest, transceiver, _getTransceiverInfosStorage()[transceiver].index
        );
    }

    /*
     * @dev pause the Transceiver.
     */
    function pause() public onlyOwnerOrPauser {
        _pause();
    }

    /// @dev Returns the bitmap of attestations from enabled transceivers for a given message.
    function _getMessageAttestations(bytes32 digest) internal view returns (uint64) {
        uint64 enabledTransceiverBitmap = _getEnabledTransceiversBitmap();
        return
            _getMessageAttestationsStorage()[digest].attestedTransceivers & enabledTransceiverBitmap;
    }

    function _getEnabledTransceiverAttestedToMessage(
        bytes32 digest,
        uint8 index
    ) internal view returns (bool) {
        return _getMessageAttestations(digest) & uint64(1 << index) != 0;
    }

    function setOutboundLimit(uint256 limit) external onlyOwner {
        _setOutboundLimit(_nttNormalize(limit));
    }

    function setInboundLimit(uint256 limit, uint16 chainId_) external onlyOwner {
        _setInboundLimit(_nttNormalize(limit), chainId_);
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
            queuedTransfer.transceiverInstructions
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
            normalizedAmount = _nttNormalize(amount);
            // don't deposit dust that can not be bridged due to the decimal shift
            uint256 newAmount = _nttDenormalize(normalizedAmount);
            if (amount != newAmount) {
                revert TransferAmountHasDust(amount, amount - newAmount);
            }
        }

        return normalizedAmount;
    }

    /// @dev Simple quality of life transfer method that doesn't deal with queuing or passing transceiver instructions.
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) external payable nonReentrant whenNotPaused returns (uint64) {
        return _transferEntryPoint(amount, recipientChain, recipient, false, new bytes(1));
    }

    /// @notice Called by the user to send the token cross-chain.
    ///         This function will either lock or burn the sender's tokens.
    ///         Finally, this function will call into the Transceiver contracts to send a message with the incrementing sequence number and the token transfer payload.
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
                    transceiverInstructions
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
            sequence,
            normalizedAmount,
            recipientChain,
            recipient,
            msg.sender,
            transceiverInstructions
        );
    }

    function _transfer(
        uint64 sequence,
        NormalizedAmount memory amount,
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
                refundToSender(excessValue);
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

        emit TransferSent(recipient, _nttDenormalize(amount), recipientChain, seq);

        // return the sequence number
        return sequence;
    }

    /// @dev Verify that the peer address saved for `sourceChainId` matches the `peerAddress`.
    function _verifyPeer(uint16 sourceChainId, bytes32 peerAddress) internal view {
        if (getPeer(sourceChainId) != peerAddress) {
            revert InvalidPeer(sourceChainId, peerAddress);
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
    ///      This function will decode the payload as an NttManagerMessage to extract the sequence, msgType, and other parameters.
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

        NormalizedAmount memory nativeTransferAmount = _nttFixDecimals(nativeTokenTransfer.amount);

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

    function _mintOrUnlockToRecipient(
        bytes32 digest,
        address recipient,
        NormalizedAmount memory amount
    ) internal {
        // calculate proper amount of tokens to unlock/mint to recipient
        // denormalize the amount
        uint256 denormalizedAmount = _nttDenormalize(amount);

        emit TransferRedeemed(digest);

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

    function getPeer(uint16 chainId_) public view returns (bytes32) {
        return _getPeersStorage()[chainId_];
    }

    /// @notice this sets the corresponding peer.
    /// @dev The nttManager that executes the message sets the source nttManager as the peer.
    function setPeer(uint16 peerChainId, bytes32 peerContract) public onlyOwner {
        if (peerChainId == 0) {
            revert InvalidPeerChainIdZero();
        }
        if (peerContract == bytes32(0)) {
            revert InvalidPeerZeroAddress();
        }

        bytes32 oldPeerContract = _getPeersStorage()[peerChainId];

        _getPeersStorage()[peerChainId] = peerContract;

        emit PeerUpdated(peerChainId, oldPeerContract, peerContract);
    }

    function transceiverAttestedToMessage(bytes32 digest, uint8 index) public view returns (bool) {
        return
            _getMessageAttestationsStorage()[digest].attestedTransceivers & uint64(1 << index) == 1;
    }

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

    // @dev Count the number of attestations from enabled transceivers for a given message.
    function messageAttestations(bytes32 digest) public view returns (uint8 count) {
        return countSetBits(_getMessageAttestations(digest));
    }

    function tokenDecimals() public view override(INttManager, RateLimiter) returns (uint8) {
        return tokenDecimals_;
    }

    /// ============== INVARIANTS =============================================

    /// @dev When we add new immutables, this function should be updated
    function _checkImmutables() internal view override {
        assert(this.token() == token);
        assert(this.mode() == mode);
        assert(this.chainId() == chainId);
        assert(this.rateLimitDuration() == rateLimitDuration);
    }

    function _checkRegisteredTransceiversInvariants() internal view {
        if (_getRegisteredTransceiversStorage().length != _getNumTransceiversStorage().registered) {
            revert RetrievedIncorrectRegisteredTransceivers(
                _getRegisteredTransceiversStorage().length, _getNumTransceiversStorage().registered
            );
        }
    }

    function _checkThresholdInvariants() internal view {
        uint8 threshold = _getThresholdStorage().num;
        _NumTransceivers memory numTransceivers = _getNumTransceiversStorage();

        // invariant: threshold <= enabledTransceivers.length
        if (threshold > numTransceivers.enabled) {
            revert ThresholdTooHigh(threshold, numTransceivers.enabled);
        }

        if (numTransceivers.registered > 0) {
            if (threshold == 0) {
                revert ZeroThreshold();
            }
        }
    }
}

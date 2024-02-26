// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "../libraries/external/OwnableUpgradeable.sol";
import "../libraries/external/ReentrancyGuardUpgradeable.sol";
import "../libraries/TransceiverStructs.sol";
import "../libraries/TransceiverHelpers.sol";
import "../libraries/RateLimiter.sol";
import "../libraries/PausableOwnable.sol";
import "../libraries/Implementation.sol";
import "../libraries/TrimmedAmount.sol";

import "../interfaces/INttManager.sol";
import "../interfaces/INttManagerState.sol";
import "../interfaces/INttManagerEvents.sol";
import "../interfaces/INTTToken.sol";
import "../interfaces/ITransceiver.sol";

import "./TransceiverRegistry.sol";

abstract contract NttManagerState is
    INttManagerState,
    INttManagerEvents,
    RateLimiter,
    TransceiverRegistry,
    PausableOwnable,
    ReentrancyGuardUpgradeable,
    Implementation
{
    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;
    // =============== Immutables ============================================================

    address public immutable token;
    address immutable deployer;
    INttManager.Mode public immutable mode;
    uint16 public immutable chainId;
    uint256 immutable evmChainId;
    uint8 public immutable tokenDecimals_;

    // =============== Setup =================================================================

    constructor(
        address _token,
        INttManager.Mode _mode,
        uint16 _chainId,
        uint64 _rateLimitDuration
    ) RateLimiter(_rateLimitDuration) {
        token = _token;
        tokenDecimals_ = _initializeTokenDecimals();
        mode = _mode;
        chainId = _chainId;
        evmChainId = block.chainid;
        // save the deployer (check this on initialization)
        deployer = msg.sender;
    }

    function __NttManager_init() internal onlyInitializing {
        // check if the owner is the deployer of this contract
        if (msg.sender != deployer) {
            revert UnexpectedDeployer(deployer, msg.sender);
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

    // =============== Storage ==============================================================

    bytes32 private constant MESSAGE_ATTESTATIONS_SLOT =
        bytes32(uint256(keccak256("ntt.messageAttestations")) - 1);

    bytes32 private constant MESSAGE_SEQUENCE_SLOT =
        bytes32(uint256(keccak256("ntt.messageSequence")) - 1);

    bytes32 private constant PEERS_SLOT = bytes32(uint256(keccak256("ntt.peers")) - 1);

    bytes32 private constant THRESHOLD_SLOT = bytes32(uint256(keccak256("ntt.threshold")) - 1);

    // =============== Storage Getters/Setters ==============================================

    function _getThresholdStorage() private pure returns (INttManager._Threshold storage $) {
        uint256 slot = uint256(THRESHOLD_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getMessageAttestationsStorage()
        internal
        pure
        returns (mapping(bytes32 => INttManager.AttestationInfo) storage $)
    {
        uint256 slot = uint256(MESSAGE_ATTESTATIONS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getMessageSequenceStorage() internal pure returns (INttManager._Sequence storage $) {
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

    // =============== Public Getters ========================================================

    /// @inheritdoc INttManagerState
    function getMode() public view returns (uint8) {
        return uint8(mode);
    }

    /// @inheritdoc INttManagerState
    function getThreshold() public view returns (uint8) {
        return _getThresholdStorage().num;
    }

    /// @inheritdoc INttManagerState
    function isMessageApproved(bytes32 digest) public view returns (bool) {
        uint8 threshold = getThreshold();
        return messageAttestations(digest) >= threshold && threshold > 0;
    }

    /// @inheritdoc INttManagerState
    function nextMessageSequence() external view returns (uint64) {
        return _getMessageSequenceStorage().num;
    }

    /// @inheritdoc INttManagerState
    function isMessageExecuted(bytes32 digest) public view returns (bool) {
        return _getMessageAttestationsStorage()[digest].executed;
    }

    /// @inheritdoc INttManagerState
    function getPeer(uint16 chainId_) public view returns (bytes32) {
        return _getPeersStorage()[chainId_];
    }

    /// @inheritdoc INttManagerState
    function transceiverAttestedToMessage(bytes32 digest, uint8 index) public view returns (bool) {
        return
            _getMessageAttestationsStorage()[digest].attestedTransceivers & uint64(1 << index) == 1;
    }

    /// @inheritdoc INttManagerState
    function messageAttestations(bytes32 digest) public view returns (uint8 count) {
        return countSetBits(_getMessageAttestations(digest));
    }

    // =============== ADMIN ==============================================================

    /// @inheritdoc INttManagerState
    function upgrade(address newImplementation) external onlyOwner {
        _upgrade(newImplementation);
    }

    /// @inheritdoc INttManagerState
    function pause() public onlyOwnerOrPauser {
        _pause();
    }

    /// @notice Transfer ownership of the Manager contract and all Endpoint contracts to a new owner.
    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
        // loop through all the registered transceivers and set the new owner of each transceiver to the newOwner
        address[] storage _registeredTransceivers = _getRegisteredTransceiversStorage();
        _checkRegisteredTransceiversInvariants();

        for (uint256 i = 0; i < _registeredTransceivers.length; i++) {
            ITransceiver(_registeredTransceivers[i]).transferTransceiverOwnership(newOwner);
        }
    }

    /// @inheritdoc INttManagerState
    function setTransceiver(address transceiver) external onlyOwner {
        _setTransceiver(transceiver);

        INttManager._Threshold storage _threshold = _getThresholdStorage();
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

    /// @inheritdoc INttManagerState
    function removeTransceiver(address transceiver) external onlyOwner {
        _removeTransceiver(transceiver);

        INttManager._Threshold storage _threshold = _getThresholdStorage();
        uint8 numEnabledTransceivers = _getNumTransceiversStorage().enabled;

        if (numEnabledTransceivers < _threshold.num) {
            _threshold.num = numEnabledTransceivers;
        }

        emit TransceiverRemoved(transceiver, _threshold.num);
    }

    /// @inheritdoc INttManagerState
    function setThreshold(uint8 threshold) external onlyOwner {
        if (threshold == 0) {
            revert ZeroThreshold();
        }

        INttManager._Threshold storage _threshold = _getThresholdStorage();
        uint8 oldThreshold = _threshold.num;

        _threshold.num = threshold;
        _checkThresholdInvariants();

        emit ThresholdChanged(oldThreshold, threshold);
    }

    /// @inheritdoc INttManagerState
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

    /// @inheritdoc INttManagerState
    function setOutboundLimit(uint256 limit) external onlyOwner {
        _setOutboundLimit(limit.trim(tokenDecimals_));
    }

    /// @inheritdoc INttManagerState
    function setInboundLimit(uint256 limit, uint16 chainId_) external onlyOwner {
        _setInboundLimit(limit.trim(tokenDecimals_), chainId_);
    }

    // =============== Internal ==============================================================

    function _setTransceiverAttestedToMessage(bytes32 digest, uint8 index) internal {
        _getMessageAttestationsStorage()[digest].attestedTransceivers |= uint64(1 << index);
    }

    function _setTransceiverAttestedToMessage(bytes32 digest, address transceiver) internal {
        _setTransceiverAttestedToMessage(digest, _getTransceiverInfosStorage()[transceiver].index);

        emit MessageAttestedTo(
            digest, transceiver, _getTransceiverInfosStorage()[transceiver].index
        );
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

    function _useMessageSequence() internal returns (uint64 currentSequence) {
        currentSequence = _getMessageSequenceStorage().num;
        _getMessageSequenceStorage().num++;
    }

    function _initializeTokenDecimals() internal view returns (uint8) {
        (, bytes memory queriedDecimals) = token.staticcall(abi.encodeWithSignature("decimals()"));
        return abi.decode(queriedDecimals, (uint8));
    }

    /// ============== Invariants =============================================

    /// @dev When we add new immutables, this function should be updated
    function _checkImmutables() internal view override {
        assert(this.token() == token);
        assert(this.tokenDecimals_() == tokenDecimals_);
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

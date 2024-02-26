// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";

import "./libraries/TransceiverHelpers.sol";
import "./libraries/TransceiverStructs.sol";
import "./interfaces/IWormholeTransceiver.sol";
import "./interfaces/ISpecialRelayer.sol";
import "./interfaces/INttManager.sol";
import "./Transceiver.sol";

contract WormholeTransceiver is Transceiver, IWormholeTransceiver, IWormholeReceiver {
    using BytesParsing for bytes;

    uint256 public constant GAS_LIMIT = 500000;
    uint8 public immutable consistencyLevel;

    /// @dev Prefix for all TransceiverMessage payloads
    ///      This is 0x99'E''W''H'
    /// @notice Magic string (constant value set by messaging provider) that idenfies the payload as an transceiver-emitted payload.
    ///         Note that this is not a security critical field. It's meant to be used by messaging providers to identify which messages are Transceiver-related.
    bytes4 constant WH_TRANSCEIVER_PAYLOAD_PREFIX = 0x9945FF10;

    /// @dev Prefix for all Wormhole transceiver initialisation payloads
    ///      This is bytes4(keccak256("WormholeTransceiverInit"))
    bytes4 constant WH_TRANSCEIVER_INIT_PREFIX = 0x9c23bd3b;

    /// @dev Prefix for all Wormhole peer registration payloads
    ///      This is bytes4(keccak256("WormholePeerRegistration"))
    bytes4 constant WH_PEER_REGISTRATION_PREFIX = 0x18fc67c2;

    IWormhole public immutable wormhole;
    IWormholeRelayer public immutable wormholeRelayer;
    ISpecialRelayer public immutable specialRelayer;
    uint256 public immutable wormholeTransceiver_evmChainId;

    struct WormholeTransceiverInstruction {
        bool shouldSkipRelayerSend;
    }

    enum RelayingType {
        Standard,
        Special,
        Manual
    }

    /// =============== STORAGE ===============================================

    bytes32 private constant WORMHOLE_CONSUMED_VAAS_SLOT =
        bytes32(uint256(keccak256("whTransceiver.consumedVAAs")) - 1);

    bytes32 private constant WORMHOLE_PEERS_SLOT =
        bytes32(uint256(keccak256("whTransceiver.peers")) - 1);

    bytes32 private constant WORMHOLE_RELAYING_ENABLED_CHAINS_SLOT =
        bytes32(uint256(keccak256("whTransceiver.relayingEnabledChains")) - 1);

    bytes32 private constant SPECIAL_RELAYING_ENABLED_CHAINS_SLOT =
        bytes32(uint256(keccak256("whTransceiver.specialRelayingEnabledChains")) - 1);

    bytes32 private constant WORMHOLE_EVM_CHAIN_IDS =
        bytes32(uint256(keccak256("whTransceiver.evmChainIds")) - 1);

    /// =============== GETTERS/SETTERS ========================================

    function _getWormholeConsumedVAAsStorage()
        internal
        pure
        returns (mapping(bytes32 => bool) storage $)
    {
        uint256 slot = uint256(WORMHOLE_CONSUMED_VAAS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getWormholePeersStorage()
        internal
        pure
        returns (mapping(uint16 => bytes32) storage $)
    {
        uint256 slot = uint256(WORMHOLE_PEERS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getWormholeRelayingEnabledChainsStorage()
        internal
        pure
        returns (mapping(uint16 => uint256) storage $)
    {
        uint256 slot = uint256(WORMHOLE_RELAYING_ENABLED_CHAINS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getSpecialRelayingEnabledChainsStorage()
        internal
        pure
        returns (mapping(uint16 => uint256) storage $)
    {
        uint256 slot = uint256(SPECIAL_RELAYING_ENABLED_CHAINS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getWormholeEvmChainIdsStorage()
        internal
        pure
        returns (mapping(uint16 => uint256) storage $)
    {
        uint256 slot = uint256(WORMHOLE_EVM_CHAIN_IDS);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    modifier onlyRelayer() {
        if (msg.sender != address(wormholeRelayer)) {
            revert CallerNotRelayer(msg.sender);
        }
        _;
    }

    constructor(
        address nttManager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr,
        uint8 _consistencyLevel
    ) Transceiver(nttManager) {
        wormhole = IWormhole(wormholeCoreBridge);
        wormholeRelayer = IWormholeRelayer(wormholeRelayerAddr);
        specialRelayer = ISpecialRelayer(specialRelayerAddr);
        wormholeTransceiver_evmChainId = block.chainid;
        consistencyLevel = _consistencyLevel;
    }

    function _initialize() internal override {
        super._initialize();
        _initializeTransceiver();
    }

    function _initializeTransceiver() internal {
        TransceiverStructs.TransceiverInit memory init = TransceiverStructs.TransceiverInit({
            transceiverIdentifier: WH_TRANSCEIVER_INIT_PREFIX,
            nttManagerAddress: toWormholeFormat(nttManager),
            nttManagerMode: INttManager(nttManager).getMode(),
            tokenAddress: toWormholeFormat(nttManagerToken),
            tokenDecimals: INttManager(nttManager).tokenDecimals()
        });
        wormhole.publishMessage(0, TransceiverStructs.encodeTransceiverInit(init), consistencyLevel);
    }

    function _checkInvalidRelayingConfig(uint16 chainId) internal view returns (bool) {
        return isWormholeRelayingEnabled(chainId) && !isWormholeEvmChain(chainId);
    }

    function _shouldRelayViaStandardRelaying(uint16 chainId) internal view returns (bool) {
        return isWormholeRelayingEnabled(chainId) && isWormholeEvmChain(chainId);
    }

    function _quoteDeliveryPrice(
        uint16 targetChain,
        TransceiverStructs.TransceiverInstruction memory instruction
    ) internal view override returns (uint256 nativePriceQuote) {
        // Check the special instruction up front to see if we should skip sending via a relayer
        WormholeTransceiverInstruction memory weIns =
            parseWormholeTransceiverInstruction(instruction.payload);
        if (weIns.shouldSkipRelayerSend) {
            return 0;
        }

        if (_checkInvalidRelayingConfig(targetChain)) {
            revert InvalidRelayingConfig(targetChain);
        }

        if (_shouldRelayViaStandardRelaying(targetChain)) {
            (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
            return cost;
        } else if (isSpecialRelayingEnabled(targetChain)) {
            uint256 cost = specialRelayer.quoteDeliveryPrice(getNttManagerToken(), targetChain, 0);
            return cost;
        } else {
            return 0;
        }
    }

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        bytes32 recipientNttManagerAddress,
        TransceiverStructs.TransceiverInstruction memory instruction,
        bytes memory nttManagerMessage
    ) internal override {
        (
            TransceiverStructs.TransceiverMessage memory transceiverMessage,
            bytes memory encodedTransceiverPayload
        ) = TransceiverStructs.buildAndEncodeTransceiverMessage(
            WH_TRANSCEIVER_PAYLOAD_PREFIX,
            toWormholeFormat(caller),
            recipientNttManagerAddress,
            nttManagerMessage,
            new bytes(0)
        );

        WormholeTransceiverInstruction memory weIns =
            parseWormholeTransceiverInstruction(instruction.payload);

        if (!weIns.shouldSkipRelayerSend && _shouldRelayViaStandardRelaying(recipientChain)) {
            wormholeRelayer.sendPayloadToEvm{value: deliveryPayment}(
                recipientChain,
                fromWormholeFormat(getWormholePeer(recipientChain)),
                encodedTransceiverPayload,
                0,
                GAS_LIMIT
            );

            emit RelayingInfo(uint8(RelayingType.Standard), deliveryPayment);
        } else if (!weIns.shouldSkipRelayerSend && isSpecialRelayingEnabled(recipientChain)) {
            uint64 sequence =
                wormhole.publishMessage(0, encodedTransceiverPayload, consistencyLevel);
            specialRelayer.requestDelivery{value: deliveryPayment}(
                getNttManagerToken(), recipientChain, 0, sequence
            );

            emit RelayingInfo(uint8(RelayingType.Special), deliveryPayment);
        } else {
            wormhole.publishMessage(0, encodedTransceiverPayload, consistencyLevel);
            emit RelayingInfo(uint8(RelayingType.Manual), deliveryPayment);
        }

        emit SendTransceiverMessage(recipientChain, transceiverMessage);
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalMessages,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable onlyRelayer {
        if (getWormholePeer(sourceChain) != sourceAddress) {
            revert InvalidWormholePeer(sourceChain, sourceAddress);
        }

        // VAA replay protection
        // Note that this VAA is for the AR delivery, not for the raw message emitted by the source chain Transceiver contract.
        // The VAAs received by this entrypoint are different than the VAA received by the receiveMessage entrypoint.
        if (isVAAConsumed(deliveryHash)) {
            revert TransferAlreadyCompleted(deliveryHash);
        }
        _setVAAConsumed(deliveryHash);

        // We don't honor additional message in this handler.
        if (additionalMessages.length > 0) {
            revert UnexpectedAdditionalMessages();
        }

        // emit `ReceivedRelayedMessage` event
        emit ReceivedRelayedMessage(deliveryHash, sourceChain, sourceAddress);

        // parse the encoded Transceiver payload
        TransceiverStructs.TransceiverMessage memory parsedTransceiverMessage;
        TransceiverStructs.NttManagerMessage memory parsedNttManagerMessage;
        (parsedTransceiverMessage, parsedNttManagerMessage) = TransceiverStructs
            .parseTransceiverAndNttManagerMessage(WH_TRANSCEIVER_PAYLOAD_PREFIX, payload);

        _deliverToNttManager(
            sourceChain,
            parsedTransceiverMessage.sourceNttManagerAddress,
            parsedTransceiverMessage.recipientNttManagerAddress,
            parsedNttManagerMessage
        );
    }

    /// @notice Receive an attested message from the verification layer
    ///         This function should verify the encodedVm and then deliver the attestation to the transceiver nttManager contract.
    function receiveMessage(bytes memory encodedMessage) external {
        uint16 sourceChainId;
        bytes memory payload;
        (sourceChainId, payload) = _verifyMessage(encodedMessage);

        // parse the encoded Transceiver payload
        TransceiverStructs.TransceiverMessage memory parsedTransceiverMessage;
        TransceiverStructs.NttManagerMessage memory parsedNttManagerMessage;
        (parsedTransceiverMessage, parsedNttManagerMessage) = TransceiverStructs
            .parseTransceiverAndNttManagerMessage(WH_TRANSCEIVER_PAYLOAD_PREFIX, payload);

        _deliverToNttManager(
            sourceChainId,
            parsedTransceiverMessage.sourceNttManagerAddress,
            parsedTransceiverMessage.recipientNttManagerAddress,
            parsedNttManagerMessage
        );
    }

    function _verifyMessage(bytes memory encodedMessage) internal returns (uint16, bytes memory) {
        // verify VAA against Wormhole Core Bridge contract
        (IWormhole.VM memory vm, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(encodedMessage);

        // ensure that the VAA is valid
        if (!valid) {
            revert InvalidVaa(reason);
        }

        // ensure that the message came from a registered peer contract
        if (!_verifyBridgeVM(vm)) {
            revert InvalidWormholePeer(vm.emitterChainId, vm.emitterAddress);
        }

        // save the VAA hash in storage to protect against replay attacks.
        if (isVAAConsumed(vm.hash)) {
            revert TransferAlreadyCompleted(vm.hash);
        }
        _setVAAConsumed(vm.hash);

        // emit `ReceivedMessage` event
        emit ReceivedMessage(vm.hash, vm.emitterChainId, vm.emitterAddress, vm.sequence);

        return (vm.emitterChainId, vm.payload);
    }

    function _verifyBridgeVM(IWormhole.VM memory vm) internal view returns (bool) {
        checkFork(wormholeTransceiver_evmChainId);
        return getWormholePeer(vm.emitterChainId) == vm.emitterAddress;
    }

    function isVAAConsumed(bytes32 hash) public view returns (bool) {
        return _getWormholeConsumedVAAsStorage()[hash];
    }

    function _setVAAConsumed(bytes32 hash) internal {
        _getWormholeConsumedVAAsStorage()[hash] = true;
    }

    /// @notice Get the corresponding Transceiver contract on other chains that have been registered via governance.
    ///         This design should be extendable to other chains, so each Transceiver would be potentially concerned with Transceivers on multiple other chains
    ///         Note that peers are registered under wormhole chainID values
    function getWormholePeer(uint16 chainId) public view returns (bytes32) {
        return _getWormholePeersStorage()[chainId];
    }

    function setWormholePeer(uint16 peerChainId, bytes32 peerContract) external onlyOwner {
        _setWormholePeer(peerChainId, peerContract);
    }

    function _setWormholePeer(uint16 chainId, bytes32 peerContract) internal {
        if (chainId == 0) {
            revert InvalidWormholeChainIdZero();
        }
        if (peerContract == bytes32(0)) {
            revert InvalidWormholePeerZeroAddress();
        }

        bytes32 oldPeerContract = _getWormholePeersStorage()[chainId];

        // We don't want to allow updating a peer since this adds complexity in the accountant
        // If the owner makes a mistake with peer registration they should deploy a new Wormhole
        // transceiver and register this new transceiver with the NttManager
        if (oldPeerContract != bytes32(0)) {
            revert PeerAlreadySet(chainId, oldPeerContract);
        }

        _getWormholePeersStorage()[chainId] = peerContract;

        // Publish a message for this transceiver registration
        TransceiverStructs.TransceiverRegistration memory registration = TransceiverStructs
            .TransceiverRegistration({
            transceiverIdentifier: WH_PEER_REGISTRATION_PREFIX,
            transceiverChainId: chainId,
            transceiverAddress: peerContract
        });
        wormhole.publishMessage(
            0, TransceiverStructs.encodeTransceiverRegistration(registration), consistencyLevel
        );

        emit SetWormholePeer(chainId, peerContract);
    }

    function isWormholeRelayingEnabled(uint16 chainId) public view returns (bool) {
        return toBool(_getWormholeRelayingEnabledChainsStorage()[chainId]);
    }

    function setIsWormholeRelayingEnabled(uint16 chainId, bool isEnabled) external onlyOwner {
        _setIsWormholeRelayingEnabled(chainId, isEnabled);
    }

    function _setIsWormholeRelayingEnabled(uint16 chainId, bool isEnabled) internal {
        if (chainId == 0) {
            revert InvalidWormholeChainIdZero();
        }
        _getWormholeRelayingEnabledChainsStorage()[chainId] = toWord(isEnabled);

        emit SetIsWormholeRelayingEnabled(chainId, isEnabled);
    }

    function isSpecialRelayingEnabled(uint16 chainId) public view returns (bool) {
        return toBool(_getSpecialRelayingEnabledChainsStorage()[chainId]);
    }

    function _setIsSpecialRelayingEnabled(uint16 chainId, bool isEnabled) internal {
        if (chainId == 0) {
            revert InvalidWormholeChainIdZero();
        }
        _getSpecialRelayingEnabledChainsStorage()[chainId] = toWord(isEnabled);

        emit SetIsSpecialRelayingEnabled(chainId, isEnabled);
    }

    function isWormholeEvmChain(uint16 chainId) public view returns (bool) {
        return toBool(_getWormholeEvmChainIdsStorage()[chainId]);
    }

    function setIsWormholeEvmChain(uint16 chainId) external onlyOwner {
        _setIsWormholeEvmChain(chainId);
    }

    function _setIsWormholeEvmChain(uint16 chainId) internal {
        if (chainId == 0) {
            revert InvalidWormholeChainIdZero();
        }
        _getWormholeEvmChainIdsStorage()[chainId] = TRUE;

        emit SetIsWormholeEvmChain(chainId);
    }

    function parseWormholeTransceiverInstruction(bytes memory encoded)
        public
        pure
        returns (WormholeTransceiverInstruction memory instruction)
    {
        // If the user doesn't pass in any transceiver instructions then the default is false
        if (encoded.length == 0) {
            instruction.shouldSkipRelayerSend = false;
            return instruction;
        }

        uint256 offset = 0;
        (instruction.shouldSkipRelayerSend, offset) = encoded.asBoolUnchecked(offset);
        encoded.checkLength(offset);
    }

    function encodeWormholeTransceiverInstruction(WormholeTransceiverInstruction memory instruction)
        public
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(instruction.shouldSkipRelayerSend);
    }
}

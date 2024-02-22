// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";

import "./libraries/EndpointHelpers.sol";
import "./interfaces/IWormholeEndpoint.sol";
import "./interfaces/ISpecialRelayer.sol";
import "./Endpoint.sol";

abstract contract WormholeEndpoint is Endpoint, IWormholeEndpoint, IWormholeReceiver {
    using BytesParsing for bytes;

    // TODO -- fix this after some testing
    uint256 public constant GAS_LIMIT = 500000;
    uint8 public constant CONSISTENCY_LEVEL = 1;

    /// @dev Prefix for all EndpointMessage payloads
    ///      This is 0x99'E''W''H'
    /// @notice Magic string (constant value set by messaging provider) that idenfies the payload as an endpoint-emitted payload.
    ///         Note that this is not a security critical field. It's meant to be used by messaging providers to identify which messages are Endpoint-related.
    bytes4 constant WH_ENDPOINT_PAYLOAD_PREFIX = 0x9945FF10;

    IWormhole public immutable wormhole;
    IWormholeRelayer public immutable wormholeRelayer;
    ISpecialRelayer public immutable specialRelayer;
    uint256 public immutable wormholeEndpoint_evmChainId;

    struct WormholeEndpointInstruction {
        bool shouldSkipRelayerSend;
    }

    /// =============== STORAGE ===============================================

    bytes32 public constant WORMHOLE_CONSUMED_VAAS_SLOT =
        bytes32(uint256(keccak256("whEndpoint.consumedVAAs")) - 1);

    bytes32 public constant WORMHOLE_SIBLINGS_SLOT =
        bytes32(uint256(keccak256("whEndpoint.siblings")) - 1);

    bytes32 public constant WORMHOLE_RELAYING_ENABLED_CHAINS_SLOT =
        bytes32(uint256(keccak256("whEndpoint.relayingEnabledChains")) - 1);

    bytes32 public constant SPECIAL_RELAYING_ENABLED_CHAINS_SLOT =
        bytes32(uint256(keccak256("whEndpoint.specialRelayingEnabledChains")) - 1);

    bytes32 public constant WORMHOLE_EVM_CHAIN_IDS =
        bytes32(uint256(keccak256("whEndpoint.evmChainIds")) - 1);

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

    function _getWormholeSiblingsStorage()
        internal
        pure
        returns (mapping(uint16 => bytes32) storage $)
    {
        uint256 slot = uint256(WORMHOLE_SIBLINGS_SLOT);
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
        address manager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr
    ) Endpoint(manager) {
        wormhole = IWormhole(wormholeCoreBridge);
        wormholeRelayer = IWormholeRelayer(wormholeRelayerAddr);
        specialRelayer = ISpecialRelayer(specialRelayerAddr);
        wormholeEndpoint_evmChainId = block.chainid;
    }

    function _checkInvalidRelayingConfig(uint16 chainId) internal view returns (bool) {
        return isWormholeRelayingEnabled(chainId) && !isWormholeEvmChain(chainId);
    }

    function _shouldRelayViaStandardRelaying(uint16 chainId) internal view returns (bool) {
        return isWormholeRelayingEnabled(chainId) && isWormholeEvmChain(chainId);
    }

    function _quoteDeliveryPrice(
        uint16 targetChain,
        EndpointStructs.EndpointInstruction memory instruction
    ) internal view override returns (uint256 nativePriceQuote) {
        // Check the special instruction up front to see if we should skip sending via a relayer
        WormholeEndpointInstruction memory weIns =
            parseWormholeEndpointInstruction(instruction.payload);
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
            uint256 cost = specialRelayer.quoteDeliveryPrice(getManagerToken(), targetChain, 0);
            return cost;
        } else {
            return 0;
        }
    }

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        EndpointStructs.EndpointInstruction memory instruction,
        bytes memory managerMessage
    ) internal override {
        (
            EndpointStructs.EndpointMessage memory endpointMessage,
            bytes memory encodedEndpointPayload
        ) = EndpointStructs.buildAndEncodeEndpointMessage(
            WH_ENDPOINT_PAYLOAD_PREFIX, toWormholeFormat(caller), managerMessage, new bytes(0)
        );

        WormholeEndpointInstruction memory weIns =
            parseWormholeEndpointInstruction(instruction.payload);

        if (!weIns.shouldSkipRelayerSend && _shouldRelayViaStandardRelaying(recipientChain)) {
            wormholeRelayer.sendPayloadToEvm{value: deliveryPayment}(
                recipientChain,
                fromWormholeFormat(getWormholeSibling(recipientChain)),
                encodedEndpointPayload,
                0,
                GAS_LIMIT
            );
        } else if (!weIns.shouldSkipRelayerSend && isSpecialRelayingEnabled(recipientChain)) {
            uint64 sequence = wormhole.publishMessage(0, encodedEndpointPayload, CONSISTENCY_LEVEL);
            specialRelayer.requestDelivery{value: deliveryPayment}(
                getManagerToken(), recipientChain, 0, sequence
            );
        } else {
            wormhole.publishMessage(0, encodedEndpointPayload, CONSISTENCY_LEVEL);
        }

        emit SendEndpointMessage(recipientChain, endpointMessage);
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalMessages,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable onlyRelayer {
        if (getWormholeSibling(sourceChain) != sourceAddress) {
            revert InvalidWormholeSibling(sourceChain, sourceAddress);
        }

        // VAA replay protection
        // Note that this VAA is for the AR delivery, not for the raw message emitted by the source chain Endpoint contract.
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

        // parse the encoded Endpoint payload
        EndpointStructs.EndpointMessage memory parsedEndpointMessage;
        EndpointStructs.ManagerMessage memory parsedManagerMessage;
        (parsedEndpointMessage, parsedManagerMessage) =
            EndpointStructs.parseEndpointAndManagerMessage(WH_ENDPOINT_PAYLOAD_PREFIX, payload);

        _deliverToManager(
            sourceChain, parsedEndpointMessage.sourceManagerAddress, parsedManagerMessage
        );
    }

    /// @notice Receive an attested message from the verification layer
    ///         This function should verify the encodedVm and then deliver the attestation to the endpoint manager contract.
    function receiveMessage(bytes memory encodedMessage) external {
        uint16 sourceChainId;
        bytes memory payload;
        (sourceChainId, payload) = _verifyMessage(encodedMessage);

        // parse the encoded Endpoint payload
        EndpointStructs.EndpointMessage memory parsedEndpointMessage;
        EndpointStructs.ManagerMessage memory parsedManagerMessage;
        (parsedEndpointMessage, parsedManagerMessage) =
            EndpointStructs.parseEndpointAndManagerMessage(WH_ENDPOINT_PAYLOAD_PREFIX, payload);

        _deliverToManager(
            sourceChainId, parsedEndpointMessage.sourceManagerAddress, parsedManagerMessage
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

        // ensure that the message came from a registered sibling contract
        if (!_verifyBridgeVM(vm)) {
            revert InvalidWormholeSibling(vm.emitterChainId, vm.emitterAddress);
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
        checkFork(wormholeEndpoint_evmChainId);
        return getWormholeSibling(vm.emitterChainId) == vm.emitterAddress;
    }

    function isVAAConsumed(bytes32 hash) public view returns (bool) {
        return _getWormholeConsumedVAAsStorage()[hash];
    }

    function _setVAAConsumed(bytes32 hash) internal {
        _getWormholeConsumedVAAsStorage()[hash] = true;
    }

    /// @notice Get the corresponding Endpoint contract on other chains that have been registered via governance.
    ///         This design should be extendable to other chains, so each Endpoint would be potentially concerned with Endpoints on multiple other chains
    ///         Note that siblings are registered under wormhole chainID values
    function getWormholeSibling(uint16 chainId) public view returns (bytes32) {
        return _getWormholeSiblingsStorage()[chainId];
    }

    function setWormholeSibling(
        uint16 siblingChainId,
        bytes32 siblingContract
    ) external onlyOwner {
        _setWormholeSibling(siblingChainId, siblingContract);
    }

    function _setWormholeSibling(uint16 chainId, bytes32 siblingContract) internal {
        if (chainId == 0) {
            revert InvalidWormholeChainIdZero();
        }
        if (siblingContract == bytes32(0)) {
            revert InvalidWormholeSiblingZeroAddress();
        }

        bytes32 oldSiblingContract = _getWormholeSiblingsStorage()[chainId];

        _getWormholeSiblingsStorage()[chainId] = siblingContract;

        emit SetWormholeSibling(chainId, oldSiblingContract, siblingContract);
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

    function parseWormholeEndpointInstruction(bytes memory encoded)
        public
        pure
        returns (WormholeEndpointInstruction memory instruction)
    {
        uint256 offset = 0;
        (instruction.shouldSkipRelayerSend, offset) = encoded.asBoolUnchecked(offset);
        encoded.checkLength(offset);
    }

    function encodeWormholeEndpointInstruction(WormholeEndpointInstruction memory instruction)
        public
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(instruction.shouldSkipRelayerSend);
    }
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";

import "./libraries/EndpointHelpers.sol";
import "./interfaces/IWormhole.sol";
import "./interfaces/IWormholeEndpoint.sol";
import "./Endpoint.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

abstract contract WormholeEndpoint is Endpoint, IWormholeEndpoint, IWormholeReceiver {
    using BytesParsing for bytes;

    // TODO -- fix this after some testing
    uint256 public constant GAS_LIMIT = 500000;

    /// @dev Prefix for all EndpointMessage payloads
    ///      This is 0x99'E''W''H'
    /// @notice Magic string (constant value set by messaging provider) that idenfies the payload as an endpoint-emitted payload.
    ///         Note that this is not a security critical field. It's meant to be used by messaging providers to identify which messages are Endpoint-related.
    bytes4 constant WH_ENDPOINT_PAYLOAD_PREFIX = 0x9945FF10;

    IWormhole public immutable wormhole;
    IWormholeRelayer public immutable wormholeRelayer;
    uint256 public immutable wormholeEndpoint_evmChainId;

    /// =============== STORAGE ===============================================

    bytes32 public constant WORMHOLE_CONSUMED_VAAS_SLOT =
        bytes32(uint256(keccak256("whEndpoint.consumedVAAs")) - 1);

    bytes32 public constant WORMHOLE_SIBLINGS_SLOT =
        bytes32(uint256(keccak256("whEndpoint.siblings")) - 1);

    bytes32 public constant WORMHOLE_RELAYING_ENABLED_CHAINS_SLOT =
        bytes32(uint256(keccak256("whEndpoint.relayingEnabledChains")) - 1);

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
        returns (mapping(uint16 => bool) storage $)
    {
        uint256 slot = uint256(WORMHOLE_RELAYING_ENABLED_CHAINS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getWormholeEvmChainIdsStorage()
        internal
        pure
        returns (mapping(uint16 => bool) storage $)
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

    constructor(address wormholeCoreBridge, address wormholeRelayerAddr) {
        wormhole = IWormhole(wormholeCoreBridge);
        wormholeRelayer = IWormholeRelayer(wormholeRelayerAddr);
        wormholeEndpoint_evmChainId = block.chainid;
    }

    function checkInvalidRelayingConfig(uint16 chainId) internal view returns (bool) {
        return isWormholeRelayingEnabled(chainId) && !isWormholeEvmChain(chainId);
    }

    function shouldRelayViaStandardRelaying(uint16 chainId) internal view returns (bool) {
        return isWormholeRelayingEnabled(chainId) && isWormholeEvmChain(chainId);
    }

    function _quoteDeliveryPrice(uint16 targetChain)
        internal
        view
        override
        returns (uint256 nativePriceQuote)
    {
        if (checkInvalidRelayingConfig(targetChain)) {
            revert InvalidRelayingConfig(targetChain);
        }

        if (shouldRelayViaStandardRelaying(targetChain)) {
            (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
            return cost;
        } else {
            return 0;
        }
    }

    function wrapManagerMessageInEndpoint(bytes memory payload)
        internal
        pure
        returns (bytes memory encodedEndpointPayload, EndpointStructs.EndpointMessage memory)
    {
        // wrap payload in EndpointMessage
        EndpointStructs.EndpointMessage memory endpointMessage = EndpointStructs.EndpointMessage({
            prefix: WH_ENDPOINT_PAYLOAD_PREFIX,
            managerPayload: payload
        });

        return (EndpointStructs.encodeEndpointMessage(endpointMessage), endpointMessage);
    }

    function _sendMessage(uint16 recipientChain, bytes memory managerMessage) internal override {
        (
            bytes memory encodedEndpointPayload,
            EndpointStructs.EndpointMessage memory endpointMessage
        ) = wrapManagerMessageInEndpoint(managerMessage);

        if (shouldRelayViaStandardRelaying(recipientChain)) {
            wormholeRelayer.sendPayloadToEvm{value: msg.value}(
                recipientChain,
                fromWormholeFormat(getWormholeSibling(recipientChain)),
                encodedEndpointPayload,
                0,
                GAS_LIMIT
            );
        } else {
            wormhole.publishMessage(0, encodedEndpointPayload, 1);
        }

        emit SendEndpointMessage(recipientChain, endpointMessage);
    }

    /*
    * @dev Parses an encoded message and extracts information into an EndpointMessage struct.
    *
    * @param encoded The encoded bytes containing information about the EndpointMessage.
    * @return endpointMessage The parsed EndpointMessage struct.
    * @throws IncorrectPrefix if the prefix of the encoded message does not match the expected prefix.
    */
    function _parseEndpointMessage(bytes memory encoded)
        internal
        pure
        override
        returns (EndpointStructs.EndpointMessage memory endpointMessage)
    {
        uint256 offset = 0;
        bytes4 prefix;

        (prefix, offset) = encoded.asBytes4Unchecked(offset);

        if (prefix != WH_ENDPOINT_PAYLOAD_PREFIX) {
            revert EndpointStructs.IncorrectPrefix(prefix);
        }

        uint16 managerPayloadLength;
        (managerPayloadLength, offset) = encoded.asUint16Unchecked(offset);
        (endpointMessage.managerPayload, offset) =
            encoded.sliceUnchecked(offset, managerPayloadLength);

        // Check if the entire byte array has been processed
        encoded.checkLength(offset);
    }

    /// @dev Parses the payload of an Endpoint message and returns the parsed ManagerMessage struct.
    function parsePayload(bytes memory payload)
        internal
        pure
        returns (EndpointStructs.ManagerMessage memory)
    {
        // parse the encoded message payload from the Endpoint
        EndpointStructs.EndpointMessage memory parsedEndpointMessage =
            _parseEndpointMessage(payload);

        // parse the encoded message payload from the Manager
        EndpointStructs.ManagerMessage memory parsed =
            EndpointStructs.parseManagerMessage(parsedEndpointMessage.managerPayload);

        return parsed;
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
        EndpointStructs.ManagerMessage memory parsed = parsePayload(payload);

        _deliverToManager(parsed);
    }

    /// @notice Receive an attested message from the verification layer
    ///         This function should verify the encodedVm and then deliver the attestation to the endpoint manager contract.
    function receiveMessage(bytes memory encodedMessage) external {
        bytes memory payload = _verifyMessage(encodedMessage);

        // parse the encoded Endpoint payload
        EndpointStructs.ManagerMessage memory parsed = parsePayload(payload);

        _deliverToManager(parsed);
    }

    function _verifyMessage(bytes memory encodedMessage) internal returns (bytes memory) {
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

        return vm.payload;
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
        return _getWormholeRelayingEnabledChainsStorage()[chainId];
    }

    function _setIsWormholeRelayingEnabled(uint16 chainId, bool isEnabled) internal {
        if (chainId == 0) {
            revert InvalidWormholeChainIdZero();
        }
        _getWormholeRelayingEnabledChainsStorage()[chainId] = isEnabled;

        emit SetIsWormholeRelayingEnabled(chainId, isEnabled);
    }

    function isWormholeEvmChain(uint16 chainId) public view returns (bool) {
        return _getWormholeEvmChainIdsStorage()[chainId];
    }

    function _setIsWormholeEvmChain(uint16 chainId) internal {
        if (chainId == 0) {
            revert InvalidWormholeChainIdZero();
        }
        _getWormholeEvmChainIdsStorage()[chainId] = true;

        emit SetIsWormholeEvmChain(chainId);
    }
}

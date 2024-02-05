// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "wormhole-solidity-sdk/Utils.sol";

import "./libraries/EndpointHelpers.sol";
import "./interfaces/IWormhole.sol";
import "./Endpoint.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

abstract contract WormholeEndpoint is Endpoint {
    using BytesParsing for bytes;

    // TODO -- fix this after some testing
    uint256 constant _GAS_LIMIT = 500000;

    address immutable _wormholeCoreBridge;
    address immutable _wormholeRelayerAddr;
    uint256 immutable _wormholeEndpoint_evmChainId;

    /// @dev Prefix for all EndpointMessage payloads
    ///      This is 0x99'E''W''H'
    /// @notice Magic string (constant value set by messaging provider) that idenfies the payload as an endpoint-emitted payload.
    ///         Note that this is not a security critical field. It's meant to be used by messaging providers to identify which messages are Endpoint-related.
    bytes4 constant WH_ENDPOINT_PAYLOAD_PREFIX = 0x9945FF10;

    event ReceivedMessage(
        bytes32 digest, uint16 emitterChainId, bytes32 emitterAddress, uint64 sequence
    );

    event SendEndpointMessage(uint16 recipientChain, EndpointStructs.EndpointMessage message);

    error InvalidVaa(string reason);
    error InvalidWormholeSibling(uint16 chainId, bytes32 siblingAddress);
    error TransferAlreadyCompleted(bytes32 vaaHash);
    error InvalidWormholeSiblingZeroAddress();
    error InvalidWormholeSiblingChainIdZero();

    /// =============== STORAGE ===============================================

    bytes32 public constant WORMHOLE_CONSUMED_VAAS_SLOT =
        bytes32(uint256(keccak256("whEndpoint.consumedVAAs")) - 1);

    bytes32 public constant WORMHOLE_SIBLINGS_SLOT =
        bytes32(uint256(keccak256("whEndpoint.siblings")) - 1);

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

    constructor(address wormholeCoreBridge, address wormholeRelayerAddr) {
        _wormholeCoreBridge = wormholeCoreBridge;
        _wormholeRelayerAddr = wormholeRelayerAddr;
        _wormholeEndpoint_evmChainId = block.chainid;
    }

    function _quoteDeliveryPrice(uint16 targetChain)
        internal
        view
        override
        returns (uint256 nativePriceQuote)
    {
        // no delivery fee for solana (standard relaying is not yet live)
        if (targetChain == 1) {
            return 0;
        }

        (uint256 cost,) = wormholeRelayer().quoteEVMDeliveryPrice(targetChain, 0, _GAS_LIMIT);

        return cost;
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

        bytes memory encodedEndpointPayload = EndpointStructs.encodeEndpointMessage(endpointMessage);

        return (encodedEndpointPayload, endpointMessage);
    }

    function _sendMessage(uint16 recipientChain, bytes memory payload) internal override {
        (
            bytes memory encodedEndpointPayload,
            EndpointStructs.EndpointMessage memory endpointMessage
        ) = wrapManagerMessageInEndpoint(payload);

        // do not use standard relaying for solana deliveries
        if (recipientChain == 1) {
            wormhole().publishMessage(0, encodedEndpointPayload, 1);
        } else {
            wormholeRelayer().sendPayloadToEvm{value: msg.value}(
                recipientChain,
                fromWormholeFormat(getWormholeSibling(recipientChain)),
                encodedEndpointPayload,
                0,
                _GAS_LIMIT
            );
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
    }

    /// @notice Receive an attested message from the verification layer
    ///         This function should verify the encodedVm and then deliver the attestation to the endpoint manager contract.
    function _receiveMessage(bytes memory encodedMessage) internal {
        bytes memory payload = _verifyMessage(encodedMessage);
        // parse the encoded message payload from the Endpoint
        EndpointStructs.EndpointMessage memory parsedEndpointMessage =
            _parseEndpointMessage(payload);
        // parse the encoded message payload from the Manager
        EndpointStructs.ManagerMessage memory parsedManagerMessage =
            EndpointStructs.parseManagerMessage(parsedEndpointMessage.managerPayload);

        _deliverToManager(parsedManagerMessage);
    }

    function _verifyMessage(bytes memory encodedMessage) internal returns (bytes memory) {
        // verify VAA against Wormhole Core Bridge contract
        (IWormhole.VM memory vm, bool valid, string memory reason) =
            wormhole().parseAndVerifyVM(encodedMessage);

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

    function wormhole() public view returns (IWormhole) {
        return IWormhole(_wormholeCoreBridge);
    }

    function wormholeRelayer() public view returns (IWormholeRelayer) {
        return IWormholeRelayer(_wormholeRelayerAddr);
    }

    function _verifyBridgeVM(IWormhole.VM memory vm) internal view returns (bool) {
        checkFork(_wormholeEndpoint_evmChainId);
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
            revert InvalidWormholeSiblingChainIdZero();
        }
        if (siblingContract == bytes32(0)) {
            revert InvalidWormholeSiblingZeroAddress();
        }
        _getWormholeSiblingsStorage()[chainId] = siblingContract;
    }
}

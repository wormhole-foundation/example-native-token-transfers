// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./Endpoint.sol";
import "./Manager.sol";
import "./EndpointRegistry.sol";
import "./libraries/Implementation.sol";

abstract contract EndpointAndManager is Endpoint, Manager, Implementation {
    uint8 constant ENDPOINT_INDEX = 0;

    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration
    ) Manager(token, mode, chainId, rateLimitDuration) {
        uint8 index = _setEndpoint(address(this));
        assert(index == ENDPOINT_INDEX);
    }

    function _initialize() internal override {
        __Manager_init();
    }

    function _migrate() internal override {}

    /// @dev When we add new immutables, this function should be updated
    function _checkImmutables() internal view override {
        assert(this.token() == token);
        assert(this.mode() == mode);
        assert(this.chainId() == chainId);
        assert(this.evmChainId() == evmChainId);
        assert(this.rateLimitDuration() == rateLimitDuration);
    }

    function upgrade(address newImplementation) external onlyOwner {
        _upgrade(newImplementation);
    }

    function quoteDeliveryPrice(uint16 recipientChain) public view override returns (uint256) {
        return _quoteDeliveryPrice(recipientChain);
    }

    function _sendMessageToEndpoint(
        uint16 recipientChain,
        bytes memory managerMessage
    ) internal override {
        return _sendMessage(recipientChain, managerMessage);
    }

    function _deliverToManager(EndpointStructs.ManagerMessage memory payload) internal override {
        bytes32 digest = EndpointStructs.managerMessageDigest(payload);
        _setEndpointAttestedToMessage(digest, ENDPOINT_INDEX);

        return _executeMsg(payload);
    }

    function isMessageApproved(bytes32 digest) public view override returns (bool) {
        return _getEnabledEndpointAttestedToMessage(digest, ENDPOINT_INDEX);
    }

    // override this function to avoid a storage lookup. The endpoint is always enabled
    function _getEnabledEndpointsBitmap() internal pure override returns (uint64) {
        return uint64(1 << ENDPOINT_INDEX);
    }
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./Endpoint.sol";
import "./Manager.sol";
import "./EndpointRegistry.sol";

abstract contract EndpointAndManager is Endpoint, Manager {
    uint8 constant ENDPOINT_INDEX = 0;

    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint256 rateLimitDuration
    ) Manager(token, mode, chainId, rateLimitDuration) {
        uint8 index = _setEndpoint(address(this));
        assert(index == ENDPOINT_INDEX);
    }

    function __EndpointAndManager_init() internal onlyInitializing {
        __Manager_init();
    }

    function quoteDeliveryPrice(uint16 recipientChain) public view override returns (uint256) {
        return _quoteDeliveryPrice(recipientChain);
    }

    function sendMessage(uint16 recipientChain, bytes memory payload) internal override {
        return _sendMessage(recipientChain, payload);
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

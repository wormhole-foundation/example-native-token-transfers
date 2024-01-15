// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./Endpoint.sol";
import "./EndpointManager.sol";
import "./EndpointRegistry.sol";

abstract contract EndpointAndManager is Endpoint, EndpointManager {
    uint8 constant ENDPOINT_INDEX = 0;

    constructor(address token, Mode mode, uint16 chainId) EndpointManager(token, mode, chainId) {
        uint8 index = _setEndpoint(address(this));
        assert(index == ENDPOINT_INDEX);
    }

    function quoteDeliveryPrice(uint16 recipientChain) public view override returns (uint256) {
        return _quoteDeliveryPrice(recipientChain);
    }

    function sendMessage(uint16 recipientChain, bytes memory payload) internal override {
        return _sendMessage(recipientChain, payload);
    }

    function _deliverToManager(EndpointStructs.EndpointManagerMessage memory payload)
        internal
        override
    {
        bytes32 digest = EndpointStructs.endpointManagerMessageDigest(payload);
        _setEndpointAttestedToMessage(digest, ENDPOINT_INDEX);

        return _executeMsg(payload);
    }

    function isMessageApproved(bytes32 digest) public view override returns (bool) {
        return _getEnabledEndpointAttestedToMessage(digest, ENDPOINT_INDEX);
    }

    // override this function to avoid a storage lookup. The endpoint is always enabled
    function _getEnabledEndpointsBitmap() internal pure override returns (uint64) {
        return 0x1;
    }

    function setSibling(
        uint16 siblingChainId,
        bytes32 siblingContract
    ) external override onlyOwner {
        _setSibling(siblingChainId, siblingContract);
    }
}

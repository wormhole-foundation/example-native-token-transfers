// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./Endpoint.sol";
import "./EndpointManager.sol";

abstract contract EndpointAndManager is Endpoint, EndpointManager {
    constructor(address token, Mode mode, uint16 chainId) EndpointManager(token, mode, chainId) {}

    function quoteDeliveryPrice(uint16 recipientChain) public view override returns (uint256) {
        return _quoteDeliveryPrice(recipientChain);
    }

    function sendMessage(uint16 recipientChain, bytes memory payload) internal override {
        return _sendMessage(recipientChain, payload);
    }

    function _deliverToManager(bytes memory payload) internal override {
        // TODO: this relies on the Endpoint implementation to replay protect messages.
        return _executeMsg(payload);
    }

    function setSibling(
        uint16 siblingChainId,
        bytes32 siblingContract
    ) external override onlyOwner {
        _setSibling(siblingChainId, siblingContract);
    }
}

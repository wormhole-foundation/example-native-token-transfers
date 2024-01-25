// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./Endpoint.sol";
import "./interfaces/IManagerStandalone.sol";
import "./interfaces/IEndpointStandalone.sol";

abstract contract EndpointStandalone is IEndpointStandalone, Endpoint {
    /// updating bridgeManager requires a new Endpoint deployment.
    /// Projects should implement their own governance to remove the old Endpoint contract address and then add the new one.
    address immutable _manager;

    constructor(address manager) {
        _manager = manager;
    }

    modifier onlyManager() {
        if (msg.sender != _manager) {
            revert CallerNotManager(msg.sender);
        }
        _;
    }

    /// @notice Called by the BridgeManager contract to send a cross-chain message.
    function sendMessage(
        uint16 recipientChain,
        bytes memory payload
    ) external payable onlyManager {
        _sendMessage(recipientChain, payload);
    }

    function quoteDeliveryPrice(uint16 targetChain) external view override returns (uint256) {
        return _quoteDeliveryPrice(targetChain);
    }

    function _deliverToManager(EndpointStructs.ManagerMessage memory payload) internal override {
        // forward the VAA payload to the endpoint manager contract
        IManagerStandalone(_manager).attestationReceived(payload);
    }

    function setSibling(uint16 chainId, bytes32 siblingContract) external onlyManager {
        _setSibling(chainId, siblingContract);
    }
}

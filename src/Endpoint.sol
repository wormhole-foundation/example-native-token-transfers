// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./interfaces/IEndpoint.sol";

abstract contract Endpoint is IEndpoint {
    // Mapping of siblings on other chains
    mapping(uint16 => bytes32) _siblings;

    function _sendMessage(uint16 recipientChain, bytes memory payload) internal virtual;

    /// @notice Receive an attested message from the verification layer
    ///         This function should verify the encodedVm and then call attestationReceived on the endpoint manager contract.
    function receiveMessage(bytes memory encodedMessage) external {
        bytes memory payload = _verifyMessage(encodedMessage);
        _deliverToManager(payload);
    }

    function _verifyMessage(bytes memory encodedMessage) internal virtual returns (bytes memory);

    function _deliverToManager(bytes memory payload) internal virtual;

    function _quoteDeliveryPrice(uint16 targetChain) internal view virtual returns (uint256);

    /// @notice Get the corresponding Endpoint contract on other chains that have been registered via governance.
    ///         This design should be extendable to other chains, so each Endpoint would be potentially concerned with Endpoints on multiple other chains
    ///         Note that siblings are registered under wormhole chainID values
    function getSibling(uint16 chainId) public view returns (bytes32) {
        return _siblings[chainId];
    }

    function _setSibling(uint16 chainId, bytes32 siblingContract) internal {
        if (siblingContract == bytes32(0)) {
            revert InvalidSiblingZeroAddress();
        }
        _siblings[chainId] = siblingContract;
    }
}

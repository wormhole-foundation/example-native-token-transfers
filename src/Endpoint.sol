// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./libraries/EndpointStructs.sol";

abstract contract Endpoint {
    function _sendMessage(uint16 recipientChain, bytes memory payload) internal virtual;

    function _deliverToManager(EndpointStructs.ManagerMessage memory payload) internal virtual;

    function _quoteDeliveryPrice(uint16 targetChain) internal view virtual returns (uint256);
}

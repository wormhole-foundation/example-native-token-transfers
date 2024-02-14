// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./libraries/EndpointStructs.sol";
import "./libraries/PausableOwnable.sol";

abstract contract Endpoint is PausableOwnable {
    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        bytes memory managerMessage
    ) internal virtual;

    function _deliverToManager(EndpointStructs.ManagerMessage memory payload) internal virtual;

    function _quoteDeliveryPrice(uint16 targetChain) internal view virtual returns (uint256);

    function _parseEndpointMessage(bytes memory encoded)
        internal
        pure
        virtual
        returns (EndpointStructs.EndpointMessage memory endpointMessage);
}

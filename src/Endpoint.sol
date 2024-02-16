// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./libraries/EndpointStructs.sol";
import "./libraries/PausableOwnable.sol";

abstract contract Endpoint is PausableOwnable {
    function _sendMessage(
        address token,
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        EndpointStructs.EndpointInstruction memory endpointInstruction,
        bytes memory managerMessage
    ) internal virtual;

    function _deliverToManager(
        uint16 sourceChainId,
        bytes32 sourceManagerAddress,
        EndpointStructs.ManagerMessage memory payload
    ) internal virtual;

    function _quoteDeliveryPrice(
        address token,
        uint16 targetChain,
        EndpointStructs.EndpointInstruction memory endpointInstruction
    ) internal view virtual returns (uint256);

    /// @notice pause the endpoint
    function _pauseEndpoint() internal {
        _pause();
    }
}

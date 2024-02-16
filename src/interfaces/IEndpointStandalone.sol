// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/EndpointStructs.sol";

interface IEndpointStandalone {
    error CallerNotManager(address caller);

    function quoteDeliveryPrice(uint16 recipientChain) external view returns (uint256);

    function sendMessage(
        uint16 recipientChain,
        EndpointStructs.EndpointInstruction memory instruction,
        bytes memory managerMessage
    ) external payable;

    function upgrade(address newImplementation) external;
}

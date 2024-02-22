// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/EndpointStructs.sol";

interface IEndpoint {
    error CallerNotManager(address caller);
    error CannotRenounceEndpointOwnership(address currentOwner);
    error CannotTransferEndpointOwnership(address currentOwner, address newOwner);
    error UnexpectedRecipientManagerAddress(
        bytes32 recipientManagerAddress, bytes32 expectedRecipientManagerAddress
    );

    function quoteDeliveryPrice(
        uint16 recipientChain,
        EndpointStructs.EndpointInstruction memory instruction
    ) external view returns (uint256);

    function sendMessage(
        uint16 recipientChain,
        EndpointStructs.EndpointInstruction memory instruction,
        bytes memory managerMessage,
        bytes32 recipientManagerAddress
    ) external payable;

    function upgrade(address newImplementation) external;

    function transferEndpointOwnership(address newOwner) external;
}

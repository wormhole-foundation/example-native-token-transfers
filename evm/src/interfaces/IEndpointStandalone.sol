// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.0 <0.9.0;

interface IEndpointStandalone {
    error CallerNotManager(address caller);

    function quoteDeliveryPrice(uint16 recipientChain) external view returns (uint256);

    function sendMessage(uint16 recipientChain, bytes memory managerMessage) external payable;

    function upgrade(address newImplementation) external;
}

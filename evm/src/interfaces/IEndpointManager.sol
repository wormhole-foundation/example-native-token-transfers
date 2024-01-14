// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

interface IEndpointManager {
    error CallerNotEndpoint(address caller);
    error DeliveryPaymentTooLow(uint256 requiredPayment, uint256 providedPayment);
    error MessageAttestationAlreadyReceived(bytes32 msgHash, address endpoint);
    error MessageAlreadyExecuted(bytes32 msgHash);
    error UnexpectedEndpointManagerMessageType(uint8 msgType);
    error InvalidTargetChain(uint16 targetChain, uint16 thisChain);
    error InvalidEndpointZeroAddress();
    error ZeroAmount();
    error EndpointAlreadyEnabled(address endpoint);
    error NonRegisteredEndpoint(address endpoint);
    error DisabledEndpoint(address endpoint);
    error TooManyEndpoints();
    error ZeroThreshold();
    error ThresholdTooHigh(uint256 threshold, uint256 endpoints);
    error InvalidAddressLength(uint256 length);

    event EndpointAdded(address endpoint);
    event EndpointRemoved(address endpoint);

    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) external payable returns (uint64 msgId);

    function quoteDeliveryPrice(uint16 recipientChain) external view returns (uint256);

    function setSibling(uint16 siblingChainId, bytes32 siblingContract) external;

    function nextSequence() external view returns (uint64);

    function token() external view returns (address);
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

interface IEndpointManager {
    error DeliveryPaymentTooLow(uint256 requiredPayment, uint256 providedPayment);
    error MessageAttestationAlreadyReceived(bytes32 msgHash, address endpoint);
    error MessageAlreadyExecuted(bytes32 msgHash);
    error MessageNotApproved(bytes32 msgHash);
    error UnexpectedEndpointManagerMessageType(uint8 msgType);
    error InvalidTargetChain(uint16 targetChain, uint16 thisChain);
    error ZeroAmount();
    error InvalidAddressLength(uint256 length);
    error NotEnoughOutboundCapacity(uint256 currentCapacity, uint256 amount);

    struct RateLimitParams {
        uint256 limit;
        uint256 currentCapacity;
        uint256 lastTxTimestamp;
        uint256 ratePerSecond;
    }

    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) external payable returns (uint64 msgId);

    function quoteDeliveryPrice(uint16 recipientChain) external view returns (uint256);

    function setSibling(uint16 siblingChainId, bytes32 siblingContract) external;

    function setOutboundLimit(uint256 limit) external;

    function getOutboundLimitParams() external view returns (RateLimitParams memory);

    function getCurrentOutboundCapacity() external view returns (uint256);

    function nextSequence() external view returns (uint64);

    function token() external view returns (address);
}

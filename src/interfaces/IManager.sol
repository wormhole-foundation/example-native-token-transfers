// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

interface IManager {
    error DeliveryPaymentTooLow(uint256 requiredPayment, uint256 providedPayment);
    error MessageAttestationAlreadyReceived(bytes32 msgHash, address endpoint);
    error MessageAlreadyExecuted(bytes32 msgHash);
    error MessageNotApproved(bytes32 msgHash);
    error UnexpectedManagerMessageType(uint8 msgType);
    error InvalidTargetChain(uint16 targetChain, uint16 thisChain);
    error ZeroAmount();
    error InvalidAddressLength(uint256 length);
    error NotEnoughOutboundCapacity(uint256 currentCapacity, uint256 amount);
    error InvalidMode(uint8 mode);
    error QueuedTransferNotFound(uint64 queueSequence);
    error QueuedTransferStillQueued(uint64 queueSequence, uint256 transferTimestamp);

    struct RateLimitParams {
        uint256 limit;
        uint256 currentCapacity;
        uint256 lastTxTimestamp;
        uint256 ratePerSecond;
    }

    struct OutboundQueuedTransfer {
        uint256 amount;
        bytes32 recipient;
        uint256 txTimestamp;
        uint16 recipientChain;
    }

    struct InboundQueuedTransfer {
        uint256 amount;
        uint256 txTimestamp;
        address recipient;
    }

    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bool shouldQueue
    ) external payable returns (uint64 msgId);

    function completeOutboundQueuedTransfer(uint64 queueSequence)
        external
        payable
        returns (uint64 msgSequence);

    function completeInboundQueuedTransfer(uint64 queueSequence) external;

    function quoteDeliveryPrice(uint16 recipientChain) external view returns (uint256);

    function setSibling(uint16 siblingChainId, bytes32 siblingContract) external;

    function setOutboundLimit(uint256 limit) external;

    function getOutboundLimitParams() external view returns (RateLimitParams memory);

    function getCurrentOutboundCapacity() external view returns (uint256);

    function getOutboundQueuedTransfer(uint64 queueSequence)
        external
        view
        returns (OutboundQueuedTransfer memory);

    function setInboundLimit(uint256 limit, uint16 chainId) external;

    function getInboundLimitParams(uint16 chainId) external view returns (RateLimitParams memory);

    function getCurrentInboundCapacity(uint16 chainId) external view returns (uint256);

    function getInboundQueuedTransfer(uint64 queueSequence)
        external
        view
        returns (InboundQueuedTransfer memory);

    function nextMessageSequence() external view returns (uint64);

    function nextOutboundQueueSequence() external view returns (uint64);

    function nextInboundQueueSequence() external view returns (uint64);

    function token() external view returns (address);
}

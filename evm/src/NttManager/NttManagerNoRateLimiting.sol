// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./NttManager.sol";

contract NttManagerNoRateLimiting is NttManager {
    constructor(
        address _token,
        Mode _mode,
        uint16 _chainId
    ) NttManager(_token, _mode, _chainId, 0, true) {}

    // ==================== Override RateLimiter functions =========================

    function _setOutboundLimit(
        TrimmedAmount // limit
    ) internal override {}

    function _setInboundLimit(TrimmedAmount limit, uint16 chainId_) internal override {}

    // ==================== Unimplemented External Interface =================================

    function getInboundLimitParams(
        uint16 chainId_
    ) public view override returns (RateLimitParams memory rateLimitParams) {}

    function getOutboundLimitParams() public pure override returns (RateLimitParams memory) {}

    /// @notice Not used, always returns max value of uint256.
    function getCurrentOutboundCapacity() public pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Not used, always reverts with NotImplemented.
    function getOutboundQueuedTransfer(
        uint64 // queueSequence
    ) public pure override returns (OutboundQueuedTransfer memory) {
        revert NotImplemented();
    }

    /// @notice Not used, always returns max value of uint256.
    function getCurrentInboundCapacity(
        uint16 // chainId
    ) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Not used, always reverts with NotImplemented.
    function getInboundQueuedTransfer(
        bytes32 // digest
    ) public pure override returns (InboundQueuedTransfer memory) {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function completeInboundQueuedTransfer(
        bytes32 // digest
    ) external view override whenNotPaused {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function completeOutboundQueuedTransfer(
        uint64 // messageSequence
    ) external payable override whenNotPaused returns (uint64) {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function cancelOutboundQueuedTransfer(
        uint64 // messageSequence
    ) external view override whenNotPaused {
        revert NotImplemented();
    }

    // ==================== Overridden Implementations =================================
    function _transferEntryPointRateLimitChecks(
        uint256, // amount
        uint16, // recipientChain
        bytes32, // recipient
        bytes32, // refundAddress
        bool, // shouldQueue
        bytes memory, // transceiverInstructions
        TrimmedAmount, // trimmedAmount
        uint64 // sequence
    ) internal pure override returns (bool) {
        return false;
    }

    function _executeMsgRateLimitChecks(
        bytes32, // digest
        uint16, // sourceChainId
        TrimmedAmount, // nativeTransferAmount
        address // transferRecipient
    ) internal view override whenNotPaused returns (bool) {
        return false;
    }
}

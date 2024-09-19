// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "../libraries/RateLimiter.sol";

import "../interfaces/INttManager.sol";
import "../interfaces/INttToken.sol";
import "../interfaces/IRateLimiter.sol";
import "../interfaces/IRateLimiterEvents.sol";
import "../interfaces/ITransceiver.sol";

import {ManagerBase} from "./ManagerBase.sol";
import {NttManagerBase} from "./NttManagerBase.sol";

/// @title NttManagerWithoutRateLimiting
/// @author Wormhole Project Contributors.
/// @notice The NttManager contract is responsible for managing the token
///         and associated transceivers. It is similar to the NttManager
///         but it does not use the rate limiter.
///
/// @dev Each NttManager contract is associated with a single token but
///      can be responsible for multiple transceivers.
///
/// @dev When transferring tokens, the NttManager contract will either
///      lock the tokens or burn them, depending on the mode.
///
/// @dev To initiate a transfer, the user calls the transfer function with:
///  - the amount
///  - the recipient chain
///  - the recipient address
///  - the refund address: the address to which refunds are issued for any unused gas
///    for attestations on a given transfer. If the gas limit is configured
///    to be too high, users will be refunded the difference.
///  - (optional) a flag to indicate whether the transfer should be queued
///    if the rate limit is exceeded
contract NttManagerWithoutRateLimiting is NttManagerBase, IRateLimiter, IRateLimiterEvents {
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;
    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    string public constant NTT_MANAGER_VERSION = "1.1.0";
    uint64 public immutable rateLimitDuration = 0;

    // =============== Setup =================================================================

    constructor(
        address _token,
        Mode _mode,
        uint16 _chainId
    ) NttManagerBase(_token, _mode, _chainId) {}

    // ==================== Unimplemented External Interface =================================

    /// @notice Not used, always reverts with NotImplemented.
    function setOutboundLimit(
        uint256 /*limit*/
    ) external view onlyOwner {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function setInboundLimit(uint256, /*limit*/ uint16 /*chainId*/ ) external view onlyOwner {
        revert NotImplemented();
    }

    /// @notice Not used, always returns max value of uint256.
    function getCurrentOutboundCapacity() external pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Not used, always reverts with NotImplemented.
    function getOutboundQueuedTransfer(
        uint64 /*queueSequence*/
    ) external pure returns (OutboundQueuedTransfer memory) {
        revert NotImplemented();
    }

    /// @notice Not used, always returns max value of uint256.
    function getCurrentInboundCapacity(
        uint16 /*chainId*/
    ) external pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Not used, always reverts with NotImplemented.
    function getInboundQueuedTransfer(
        bytes32 /*digest*/
    ) external pure returns (InboundQueuedTransfer memory) {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function completeInboundQueuedTransfer(
        bytes32 /*digest*/
    ) external nonReentrant whenNotPaused {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function completeOutboundQueuedTransfer(
        uint64 /*messageSequence*/
    ) external payable nonReentrant whenNotPaused returns (uint64) {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function cancelOutboundQueuedTransfer(
        uint64 /*messageSequence*/
    ) external nonReentrant whenNotPaused {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function getInboundLimitParams(
        uint16 /*chainId_*/
    ) public pure returns (RateLimitParams memory) {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function getOutboundLimitParams() public pure returns (RateLimitParams memory) {
        revert NotImplemented();
    }
}

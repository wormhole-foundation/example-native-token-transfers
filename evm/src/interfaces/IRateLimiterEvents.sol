// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/NormalizedAmount.sol";

interface IRateLimiterEvents {

    /// @notice Emitted when an inbound transfer is queued
    /// @dev Topic0
    ///      0x7f63c9251d82a933210c2b6d0b0f116252c3c116788120e64e8e8215df6f3162.
    /// @param digest The digest of the message.
    event InboundTransferQueued(bytes32 digest);

    /// @notice Emitted whenn an outbound transfer is queued.
    /// @dev Topic0
    ///      0x69add1952a6a6b9cb86f04d05f0cb605cbb469a50ae916139d34495a9991481f.
    /// @param queueSequence The location of the transfer in the queue.
    event OutboundTransferQueued(uint64 queueSequence);

    /// @notice Emitted when an outbound transfer is rate limited.
    /// @dev Topic0
    ///      0x754d657d1363ee47d967b415652b739bfe96d5729ccf2f26625dcdbc147db68b.
    /// @param sender The initial sender of the transfer.
    /// @param amount The amount to be transferred.
    /// @param currentCapacity The capacity left for transfers within the 24-hour window.
    event OutboundTransferRateLimited(
        address indexed sender, uint64 sequence, uint256 amount, uint256 currentCapacity
    );
}

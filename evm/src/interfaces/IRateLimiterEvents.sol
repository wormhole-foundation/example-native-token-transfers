// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TrimmedAmount.sol";

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
    ///      0xf33512b84e24a49905c26c6991942fc5a9652411769fc1e448f967cdb049f08a.
    /// @param sender The initial sender of the transfer.
    /// @param amount The amount to be transferred.
    /// @param currentCapacity The capacity left for transfers within the 24-hour window.
    event OutboundTransferRateLimited(
        address indexed sender, uint64 sequence, uint256 amount, uint256 currentCapacity
    );

    /// @notice Emitted when the outbound transfer limit is updated.
    /// @dev Topic0
    ///      0x7e3b0fc388be9d36273f66210aed83be975df3a9adfffa4c734033f498f362cd.
    /// @param oldLimit The old outbound limit.
    /// @param newLimit The new outbound limit.
    event OutboundTransferLimitUpdated(uint256 oldLimit, uint256 newLimit);

    /// @notice Emitted when the inbound transfer limit is updated.
    /// @dev Topic0
    ///      0x739ed886fd81a3ddc9f4b327ab69152e513cd45b26fda0c73660eaca8e119301.
    /// @param chainId The chain ID the limit is set for.
    /// @param oldLimit The old inbound limit.
    /// @param newLimit The new inbound limit.
    event InboundTransferLimitUpdated(uint16 indexed chainId, uint256 oldLimit, uint256 newLimit);
}

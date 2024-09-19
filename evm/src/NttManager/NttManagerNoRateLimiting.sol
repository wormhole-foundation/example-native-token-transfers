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
import "../interfaces/ITransceiver.sol";

import {ManagerBase} from "./ManagerBase.sol";
import "./NttManager.sol";

contract NttManagerNoRateLimiting is NttManager {
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;
    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    constructor(
        address _token,
        Mode _mode,
        uint16 _chainId
    ) NttManager(_token, _mode, _chainId, 0, true) {}

    /// @dev When we add new immutables, this function should be updated
    function _checkImmutables() internal view override {
        ManagerBase._checkImmutables();
    }

    // ==================== Override RateLimiter functions =========================

    function _setOutboundLimit(
        TrimmedAmount limit
    ) internal override {}

    function _setInboundLimit(TrimmedAmount limit, uint16 chainId_) internal override {}

    function _isOutboundAmountRateLimited(
        TrimmedAmount amount
    ) internal view override returns (bool) {
        return false;
    }

    function _enqueueInboundTransfer(
        bytes32 digest,
        TrimmedAmount amount,
        address recipient
    ) internal override {}

    function _backfillOutboundAmount(
        TrimmedAmount amount
    ) internal override {}

    function _consumeInboundAmount(TrimmedAmount amount, uint16 chainId_) internal override {}

    // ==================== Unimplemented External Interface =================================

    /// @notice Not used, always returns max value of uint256.
    function getCurrentOutboundCapacity() public view override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Not used, always reverts with NotImplemented.
    function getOutboundQueuedTransfer(
        uint64 /*queueSequence*/
    ) public view override returns (OutboundQueuedTransfer memory) {
        revert NotImplemented();
    }

    /// @notice Not used, always returns max value of uint256.
    function getCurrentInboundCapacity(
        uint16 /*chainId*/
    ) public view override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Not used, always reverts with NotImplemented.
    function getInboundQueuedTransfer(
        bytes32 /*digest*/
    ) public view override returns (InboundQueuedTransfer memory) {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function completeInboundQueuedTransfer(
        bytes32 /*digest*/
    ) external override nonReentrant whenNotPaused {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function completeOutboundQueuedTransfer(
        uint64 /*messageSequence*/
    ) external payable override nonReentrant whenNotPaused returns (uint64) {
        revert NotImplemented();
    }

    /// @notice Not used, always reverts with NotImplemented.
    function cancelOutboundQueuedTransfer(
        uint64 /*messageSequence*/
    ) external override nonReentrant whenNotPaused {
        revert NotImplemented();
    }

    // ==================== Overridden Implementations =================================

    function _transferEntryPoint(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bytes32 refundAddress,
        bool shouldQueue,
        bytes memory transceiverInstructions
    ) internal override returns (uint64) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (recipient == bytes32(0)) {
            revert InvalidRecipient();
        }

        if (refundAddress == bytes32(0)) {
            revert InvalidRefundAddress();
        }

        {
            // Lock/burn tokens before checking rate limits
            // use transferFrom to pull tokens from the user and lock them
            // query own token balance before transfer
            uint256 balanceBefore = _getTokenBalanceOf(token, address(this));

            // transfer tokens
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

            // query own token balance after transfer
            uint256 balanceAfter = _getTokenBalanceOf(token, address(this));

            // correct amount for potential transfer fees
            amount = balanceAfter - balanceBefore;
            if (mode == Mode.BURNING) {
                {
                    // NOTE: We don't account for burn fees in this code path.
                    // We verify that the user's change in balance is equal to the amount that's burned.
                    // Accounting for burn fees can be non-trivial, since there
                    // is no standard way to account for the fee if the fee amount
                    // is taken out of the burn amount.
                    // For example, if there's a fee of 1 which is taken out of the
                    // amount, then burning 20 tokens would result in a transfer of only 19 tokens.
                    // However, the difference in the user's balance would only show 20.
                    // Since there is no standard way to query for burn fee amounts with burnable tokens,
                    // and NTT would be used on a per-token basis, implementing this functionality
                    // is left to integrating projects who may need to account for burn fees on their tokens.
                    ERC20Burnable(token).burn(amount);

                    // tokens held by the contract after the operation should be the same as before
                    uint256 balanceAfterBurn = _getTokenBalanceOf(token, address(this));
                    if (balanceBefore != balanceAfterBurn) {
                        revert BurnAmountDifferentThanBalanceDiff(balanceBefore, balanceAfterBurn);
                    }
                }
            }
        }

        // trim amount after burning to ensure transfer amount matches (amount - fee)
        TrimmedAmount trimmedAmount = _trimTransferAmount(amount, recipientChain);

        // get the sequence for this transfer
        uint64 sequence = _useMessageSequence();

        return _transfer(
            sequence,
            trimmedAmount,
            recipientChain,
            recipient,
            refundAddress,
            msg.sender,
            transceiverInstructions
        );
    }

    /// @inheritdoc INttManager
    function executeMsg(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory message
    ) public override whenNotPaused {
        (bytes32 digest, bool alreadyExecuted) =
            _isMessageExecuted(sourceChainId, sourceNttManagerAddress, message);

        if (alreadyExecuted) {
            return;
        }

        TransceiverStructs.NativeTokenTransfer memory nativeTokenTransfer =
            TransceiverStructs.parseNativeTokenTransfer(message.payload);

        // verify that the destination chain is valid
        if (nativeTokenTransfer.toChain != chainId) {
            revert InvalidTargetChain(nativeTokenTransfer.toChain, chainId);
        }
        uint8 toDecimals = tokenDecimals();
        TrimmedAmount nativeTransferAmount =
            (nativeTokenTransfer.amount.untrim(toDecimals)).trim(toDecimals, toDecimals);

        address transferRecipient = fromWormholeFormat(nativeTokenTransfer.to);

        _mintOrUnlockToRecipient(digest, transferRecipient, nativeTransferAmount, false);
    }
}

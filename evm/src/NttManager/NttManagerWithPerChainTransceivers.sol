// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./NttManager.sol";

/// @title  NttManagerWithPerChainTransceivers
/// @author Wormhole Project Contributors.
/// @notice The NttManagerWithPerChainTransceivers abstract contract is an implementation of
///         NttManager that allows configuring different transceivers and thresholds
///         for each chain. You can configure a different set of send and receive
///         transceivers for each chain, and if you don't specifically enable any
///         transceivers for a chain, then all transceivers will be used for it.
///
/// @dev    All of the developer notes from `NttManager` apply here.
abstract contract NttManagerWithPerChainTransceivers is NttManager {
    constructor(
        address _token,
        Mode _mode,
        uint16 _chainId,
        uint64 _rateLimitDuration,
        bool _skipRateLimiting
    ) NttManager(_token, _mode, _chainId, _rateLimitDuration, _skipRateLimiting) {}

    // ==================== Storage slots ==========================================================

    bytes32 private constant SEND_TRANSCEIVER_BITMAP_SLOT =
        bytes32(uint256(keccak256("nttpct.sendTransceiverBitmap")) - 1);

    bytes32 private constant RECV_TRANSCEIVER_BITMAP_SLOT =
        bytes32(uint256(keccak256("nttpct.recvTransceiverBitmap")) - 1);

    // ==================== Override / implementation of transceiver stuff =========================

    /// @inheritdoc IManagerBase
    function enableSendTransceiverForChain(
        address transceiver,
        uint16 forChainId
    ) external override(ManagerBase, IManagerBase) onlyOwner {
        _enableTransceiverForChain(transceiver, forChainId, SEND_TRANSCEIVER_BITMAP_SLOT);
        emit SendTransceiverEnabledForChain(transceiver, forChainId);
    }

    /// @inheritdoc IManagerBase
    function enableRecvTransceiverForChain(
        address transceiver,
        uint16 forChainId
    ) external override(ManagerBase, IManagerBase) onlyOwner {
        _enableTransceiverForChain(transceiver, forChainId, RECV_TRANSCEIVER_BITMAP_SLOT);
        emit RecvTransceiverEnabledForChain(transceiver, forChainId);
    }

    function _enableTransceiverForChain(
        address transceiver,
        uint16 forChainId,
        bytes32 tag
    ) private {
        if (transceiver == address(0)) {
            revert InvalidTransceiverZeroAddress();
        }

        mapping(address => TransceiverInfo) storage transceiverInfos = _getTransceiverInfosStorage();
        if (!transceiverInfos[transceiver].registered) {
            revert NonRegisteredTransceiver(transceiver);
        }

        uint8 index = _getTransceiverInfosStorage()[transceiver].index;
        mapping(uint16 => _EnabledTransceiverBitmap) storage _bitmaps =
            _getPerChainTransceiverBitmapStorage(tag);
        _bitmaps[forChainId].bitmap |= uint64(1 << index);
    }

    function _isSendTransceiverEnabledForChain(
        address transceiver,
        uint16 forChainId
    ) internal view override returns (bool) {
        uint64 bitmap = _getPerChainTransceiverBitmap(forChainId, SEND_TRANSCEIVER_BITMAP_SLOT);
        uint8 index = _getTransceiverInfosStorage()[transceiver].index;
        return (bitmap & uint64(1 << index)) != 0;
    }

    function _getEnabledRecvTransceiversForChain(
        uint16 forChainId
    ) internal view returns (uint64 bitmap) {
        return _getPerChainTransceiverBitmap(forChainId, RECV_TRANSCEIVER_BITMAP_SLOT);
    }

    function _getPerChainTransceiverBitmap(
        uint16 forChainId,
        bytes32 tag
    ) private view returns (uint64 bitmap) {
        bitmap = _getPerChainTransceiverBitmapStorage(tag)[forChainId].bitmap;
        if (bitmap == 0) {
            bitmap = type(uint64).max;
        }
    }

    function _getPerChainTransceiverBitmapStorage(
        bytes32 tag
    ) private pure returns (mapping(uint16 => _EnabledTransceiverBitmap) storage $) {
        uint256 slot = uint256(tag);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    // ==================== Override / implementation of threshold stuff =========================

    /// @inheritdoc IManagerBase
    function setPerChainThreshold(
        uint16 forChainId,
        uint8 threshold
    ) external override(ManagerBase, IManagerBase) onlyOwner {
        if (threshold == 0) {
            revert ZeroThreshold();
        }

        mapping(uint16 => _Threshold) storage _threshold = _getThresholdStoragePerChain();
        uint8 oldThreshold = _threshold[forChainId].num;

        _threshold[forChainId].num = threshold;
        _checkThresholdInvariants(_threshold[forChainId].num);

        emit PerChainThresholdChanged(forChainId, oldThreshold, threshold);
    }

    function getPerChainThreshold(
        uint16 forChainId
    ) public view override(ManagerBase, IManagerBase) returns (uint8) {
        uint8 threshold = _getThresholdStoragePerChain()[forChainId].num;
        if (threshold == 0) {
            return _getThresholdStorage().num;
        }
        return threshold;
    }

    function _getThresholdStoragePerChain()
        private
        pure
        returns (mapping(uint16 => _Threshold) storage $)
    {
        // TODO: this is safe (reusing the storage slot, because the mapping
        // doesn't write into the slot itself) buy maybe we shouldn't?
        uint256 slot = uint256(THRESHOLD_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    /// @inheritdoc IManagerBase
    function isMessageApproved(
        bytes32 digest
    ) public view override(ManagerBase, IManagerBase) returns (bool) {
        uint16 sourceChainId = _getMessageAttestationsStorage()[digest].sourceChainId;
        uint8 threshold = getPerChainThreshold(sourceChainId);
        return messageAttestations(digest) >= threshold && threshold > 0;
    }

    function _getMessageAttestations(
        bytes32 digest
    ) internal view override returns (uint64) {
        AttestationInfo memory attInfo = _getMessageAttestationsStorage()[digest];
        uint64 enabledTransceiverBitmap = _getEnabledTransceiversBitmap();
        uint64 enabledTransceiversForChain =
            _getEnabledRecvTransceiversForChain(attInfo.sourceChainId);
        return attInfo.attestedTransceivers & enabledTransceiverBitmap & enabledTransceiversForChain;
    }
}

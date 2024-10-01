// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./NttManagerNoRateLimiting.sol";

/// @title  NttManagerWithPerChainTransceivers
/// @author Wormhole Project Contributors.
/// @notice The NttManagerWithPerChainTransceivers contract is an implementation of
///         NttManager that allows configuring different transceivers and thresholds
///         for each chain. You must configure the set of send and receive transceivers
///         for each chain you intend to use. Additionally, you must set the receive
///         threshold for each chain. You can disable a chain by resetting its bitmaps
///         and threshold to zero.
///
/// @dev    All of the developer notes from `NttManager` apply here.
contract NttManagerWithPerChainTransceivers is NttManagerNoRateLimiting {
    /// @notice Transceiver index is greater than the number of enabled transceivers.
    /// @dev Selector 0x770c2d3c.
    /// @param index The transceiver index that is invalid.
    /// @param len The length of the transceiver list.
    error TransceiverIndexTooLarge(uint8 index, uint256 len);

    /// @notice Transceiver index does not match the one in the list.
    /// @dev Selector 0x2f52d3e.
    /// @param index The transceiver index that is invalid.
    /// @param expectedIndex The index in the transceiver list.
    error InvalidTransceiverIndex(uint8 index, uint8 expectedIndex);

    /// @notice Transceiver with specified index is not registered.
    /// @dev Selector 0x38ab702a.
    /// @param index The index of the transceiver that is not registered.
    /// @param transceiver The address of the transceiver that is not registered.
    error TransceiverNotRegistered(uint8 index, address transceiver);

    /// @notice Transceiver with specified index is not enabled.
    /// @dev Selector 0xcc4cba2a.
    /// @param index The index of the transceiver that is not enabled.
    /// @param transceiver The address of the transceiver that is not enabled.
    error TransceiverNotEnabled(uint8 index, address transceiver);

    constructor(
        address _token,
        Mode _mode,
        uint16 _chainId
    ) NttManagerNoRateLimiting(_token, _mode, _chainId) {}

    // ==================== Storage slots ==========================================================

    bytes32 private constant SEND_TRANSCEIVER_BITMAP_SLOT =
        bytes32(uint256(keccak256("nttpct.sendTransceiverBitmap")) - 1);

    bytes32 private constant RECV_TRANSCEIVER_BITMAP_SLOT =
        bytes32(uint256(keccak256("nttpct.recvTransceiverBitmap")) - 1);

    bytes32 private constant SEND_ENABLED_CHAINS_SLOT =
        bytes32(uint256(keccak256("nttpct.sendEnabledChains")) - 1);

    bytes32 private constant RECV_ENABLED_CHAINS_SLOT =
        bytes32(uint256(keccak256("nttpct.recvEnabledChains")) - 1);

    // =============== Public Getters ========================================================

    /// @inheritdoc IManagerBase
    function getSendTransceiverBitmapForChain(
        uint16 forChainId
    ) external view override(ManagerBase, IManagerBase) returns (uint64) {
        return _getPerChainTransceiverBitmap(forChainId, SEND_TRANSCEIVER_BITMAP_SLOT);
    }

    /// @inheritdoc IManagerBase
    function getRecvTransceiverBitmapForChain(
        uint16 forChainId
    ) external view override(ManagerBase, IManagerBase) returns (uint64) {
        return _getPerChainTransceiverBitmap(forChainId, RECV_TRANSCEIVER_BITMAP_SLOT);
    }

    /// @inheritdoc IManagerBase
    function getChainsEnabledForSending()
        external
        pure
        override(ManagerBase, IManagerBase)
        returns (uint16[] memory)
    {
        return _getEnabledChainsStorage(SEND_ENABLED_CHAINS_SLOT);
    }

    /// @inheritdoc IManagerBase
    function getChainsEnabledForReceiving()
        external
        pure
        override(ManagerBase, IManagerBase)
        returns (uint16[] memory)
    {
        return _getEnabledChainsStorage(RECV_ENABLED_CHAINS_SLOT);
    }

    /// @inheritdoc IManagerBase
    function getThresholdForChain(
        uint16 forChainId
    ) public view override(ManagerBase, IManagerBase) returns (uint8) {
        return _getThresholdStoragePerChain()[forChainId].num;
    }

    // =============== Public Setters ========================================================

    /// @inheritdoc IManagerBase
    function setSendTransceiverBitmapForChain(
        uint16 forChainId,
        uint64 indexBitmap
    ) public override(ManagerBase, IManagerBase) onlyOwner {
        _validateTransceivers(indexBitmap);
        mapping(uint16 => _EnabledTransceiverBitmap) storage _bitmaps =
            _getPerChainTransceiverBitmapStorage(SEND_TRANSCEIVER_BITMAP_SLOT);
        uint64 oldBitmap = _bitmaps[forChainId].bitmap;
        _bitmaps[forChainId].bitmap = indexBitmap;

        if (indexBitmap == 0) {
            _removeChain(SEND_ENABLED_CHAINS_SLOT, forChainId);
        } else {
            _addChainIfNeeded(SEND_ENABLED_CHAINS_SLOT, forChainId);
        }

        emit SendTransceiversUpdatedForChain(forChainId, oldBitmap, indexBitmap);
    }

    /// @inheritdoc IManagerBase
    function setRecvTransceiverBitmapForChain(
        uint16 forChainId,
        uint64 indexBitmap,
        uint8 threshold
    ) public override(ManagerBase, IManagerBase) onlyOwner {
        _validateTransceivers(indexBitmap);

        // Validate the threshold against the bitmap.
        uint8 numEnabled = countSetBits(indexBitmap);
        if (threshold > numEnabled) {
            revert ThresholdTooHigh(threshold, numEnabled);
        }

        if ((numEnabled != 0) && (threshold == 0)) {
            revert ZeroThreshold();
        }

        // Update the bitmap.
        mapping(uint16 => _EnabledTransceiverBitmap) storage _bitmaps =
            _getPerChainTransceiverBitmapStorage(RECV_TRANSCEIVER_BITMAP_SLOT);
        uint64 oldBitmap = _bitmaps[forChainId].bitmap;
        _bitmaps[forChainId].bitmap = indexBitmap;

        // Update the thresold.
        mapping(uint16 => _Threshold) storage _threshold = _getThresholdStoragePerChain();
        uint8 oldThreshold = _threshold[forChainId].num;
        _threshold[forChainId].num = threshold;

        // Update the chain list.
        if (indexBitmap == 0) {
            _removeChain(RECV_ENABLED_CHAINS_SLOT, forChainId);
        } else {
            _addChainIfNeeded(RECV_ENABLED_CHAINS_SLOT, forChainId);
        }

        emit RecvTransceiversUpdatedForChain(
            forChainId, oldBitmap, indexBitmap, oldThreshold, threshold
        );
    }

    /// @inheritdoc IManagerBase
    function setTransceiversForChains(
        SetTransceiversForChainEntry[] memory params
    ) external override(ManagerBase, IManagerBase) onlyOwner {
        for (uint256 idx = 0; idx < params.length; idx++) {
            setSendTransceiverBitmapForChain(params[idx].chainId, params[idx].sendBitmap);
            setRecvTransceiverBitmapForChain(
                params[idx].chainId, params[idx].recvBitmap, params[idx].recvThreshold
            );
        }
    }

    // =============== Internal Interface Overrides ===================================================

    function _isSendTransceiverEnabledForChain(
        address transceiver,
        uint16 forChainId
    ) internal view override returns (bool) {
        uint64 bitmap = _getPerChainTransceiverBitmap(forChainId, SEND_TRANSCEIVER_BITMAP_SLOT);
        uint8 index = _getTransceiverInfosStorage()[transceiver].index;
        return (bitmap & uint64(1 << index)) != 0;
    }

    /// @inheritdoc IManagerBase
    function isMessageApproved(
        bytes32 digest
    ) public view override(ManagerBase, IManagerBase) returns (bool) {
        uint16 sourceChainId = _getMessageAttestationsStorage()[digest].sourceChainId;
        uint8 threshold = getThresholdForChain(sourceChainId);
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

    // ==================== Implementation =========================

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
    }

    function _getPerChainTransceiverBitmapStorage(
        bytes32 tag
    ) private pure returns (mapping(uint16 => _EnabledTransceiverBitmap) storage $) {
        uint256 slot = uint256(tag);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getThresholdStoragePerChain()
        private
        pure
        returns (mapping(uint16 => _Threshold) storage $)
    {
        // Reusing the global storage slot is safe because the mapping doesn't write into the slot itself.
        uint256 slot = uint256(THRESHOLD_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _validateTransceivers(
        uint64 indexBitmap
    ) internal view {
        uint8 index = 0;
        while (indexBitmap != 0) {
            if (indexBitmap & 0x01 == 1) {
                _validateTransceiver(index);
            }
            indexBitmap = indexBitmap >> 1;
            index++;
        }
    }

    function _validateTransceiver(
        uint8 index
    ) internal view {
        address[] storage _enabledTransceivers = _getEnabledTransceiversStorage();
        if (index >= _enabledTransceivers.length) {
            revert TransceiverIndexTooLarge(index, _enabledTransceivers.length);
        }

        address transceiverAddr = _enabledTransceivers[index];
        mapping(address => TransceiverInfo) storage transceiverInfos = _getTransceiverInfosStorage();

        if (transceiverInfos[transceiverAddr].index != index) {
            revert InvalidTransceiverIndex(index, transceiverInfos[transceiverAddr].index);
        }

        if (!transceiverInfos[transceiverAddr].registered) {
            revert TransceiverNotRegistered(index, transceiverAddr);
        }

        if (!transceiverInfos[transceiverAddr].enabled) {
            revert TransceiverNotEnabled(index, transceiverAddr);
        }
    }

    function _removeChain(bytes32 tag, uint16 forChainId) private {
        uint16[] storage chains = _getEnabledChainsStorage(tag);
        uint256 len = chains.length;
        for (uint256 idx = 0; (idx < len); idx++) {
            if (chains[idx] == forChainId) {
                if (len > 1) {
                    chains[idx] = chains[len - 1];
                }
                chains.pop();
                return;
            }
        }
    }

    function _addChainIfNeeded(bytes32 tag, uint16 forChainId) private {
        uint16[] storage chains = _getEnabledChainsStorage(tag);
        uint256 zeroIdx = type(uint256).max;
        uint256 len = chains.length;
        for (uint256 idx = 0; (idx < len); idx++) {
            if (chains[idx] == forChainId) {
                return;
            }
            if (chains[idx] == 0) {
                zeroIdx = idx;
            }
        }

        if (zeroIdx != type(uint256).max) {
            chains[zeroIdx] = forChainId;
        } else {
            chains.push(forChainId);
        }
    }

    // function _copyEnabledChains(bytes32 tag) uint16[] memory {
    //     uint16[] ret = new
    // }

    function _getEnabledChainsStorage(
        bytes32 tag
    ) internal pure returns (uint16[] storage $) {
        uint256 slot = uint256(tag);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }
}

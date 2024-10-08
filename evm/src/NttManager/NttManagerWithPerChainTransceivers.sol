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
    /// @notice Emitted when the sending transceivers are updated for a chain.
    /// @dev Topic0
    ///      0xe3bed59083cdad1d552b8eef7d3acc80adb78da6c6f375ae3adf5cb4823b2619
    /// @param chainId The chain that was updated.
    /// @param oldBitmap The original index bitmap.
    /// @param oldBitmap The updated index bitmap.
    event SendTransceiversUpdatedForChain(uint16 chainId, uint64 oldBitmap, uint64 newBitmap);

    /// @notice Emitted when the receivinging transceivers are updated for a chain.
    /// @dev Topic0
    ///      0xd09fdac2bd3e794a578992bfe77134765623d22a2b3201e2994f681828160f2f
    /// @param chainId The chain that was updated.
    /// @param oldBitmap The original index bitmap.
    /// @param oldBitmap The updated index bitmap.
    /// @param oldThreshold The original receive threshold.
    /// @param newThreshold The updated receive threshold.
    event RecvTransceiversUpdatedForChain(
        uint16 chainId, uint64 oldBitmap, uint64 newBitmap, uint8 oldThreshold, uint8 newThreshold
    );

    /// @notice Transceiver index does not match one in the list.
    /// @dev Selector 0x24595b41.
    /// @param index The transceiver index that is invalid.
    error InvalidTransceiverIndex(uint8 index);

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

    /// @notice The structure of a per-chain entry in the call to setTransceiversForChains.
    struct SetTransceiversForChainEntry {
        uint64 sendBitmap;
        uint64 recvBitmap;
        uint16 chainId;
        uint8 recvThreshold;
    }

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

    /// @notice Returns the bitmap of send transceivers enabled for a chain.
    /// @param forChainId The chain for which sending is enabled.
    function getSendTransceiverBitmapForChain(
        uint16 forChainId
    ) external view returns (uint64) {
        return _getPerChainTransceiverBitmap(forChainId, SEND_TRANSCEIVER_BITMAP_SLOT);
    }

    /// @notice Returns the bitmap of receive transceivers enabled for a chain.
    /// @param forChainId The chain for which receiving is enabled.
    function getRecvTransceiverBitmapForChain(
        uint16 forChainId
    ) external view returns (uint64) {
        return _getPerChainTransceiverBitmap(forChainId, RECV_TRANSCEIVER_BITMAP_SLOT);
    }

    /// @notice Returns the set of chains for which sending is enabled.
    function getChainsEnabledForSending() external pure returns (uint16[] memory) {
        return _getEnabledChainsStorage(SEND_ENABLED_CHAINS_SLOT);
    }

    /// @notice Returns the set of chains for which receiving is enabled.
    function getChainsEnabledForReceiving() external pure returns (uint16[] memory) {
        return _getEnabledChainsStorage(RECV_ENABLED_CHAINS_SLOT);
    }

    /// @notice Returns the number of Transceivers that must attest to a msgId for
    /// it to be considered valid and acted upon.
    /// @param forChainId The chain for which the threshold applies.
    function getThresholdForChain(
        uint16 forChainId
    ) public view returns (uint8) {
        return _getThresholdStoragePerChain()[forChainId].num;
    }

    // =============== Public Setters ========================================================

    /// @notice Sets the bitmap of transceivers enabled for sending for a chain.
    /// @param forChainId The chain to be updated.
    /// @param indexBitmap The bitmap of transceiver indexes that are enabled.
    function setSendTransceiverBitmapForChain(
        uint16 forChainId,
        uint64 indexBitmap
    ) public onlyOwner {
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

    /// @notice Sets the bitmap of transceivers enabled for receiving for a chain.
    /// @param forChainId The chain to be updated.
    /// @param indexBitmap The bitmap of transceiver indexes that are enabled.
    /// @param threshold The receive threshold for the chain.
    function setRecvTransceiverBitmapForChain(
        uint16 forChainId,
        uint64 indexBitmap,
        uint8 threshold
    ) public onlyOwner {
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

    /// @notice Sets the transceiver bitmaps and thresholds for a set of chains.
    /// @param params The values to be applied for a set of chains.
    function setTransceiversForChains(
        SetTransceiversForChainEntry[] memory params
    ) external onlyOwner {
        uint256 len = params.length;
        for (uint256 idx = 0; idx < len;) {
            setSendTransceiverBitmapForChain(params[idx].chainId, params[idx].sendBitmap);
            setRecvTransceiverBitmapForChain(
                params[idx].chainId, params[idx].recvBitmap, params[idx].recvThreshold
            );
            unchecked {
                ++idx;
            }
        }
    }

    // =============== Internal Interface Overrides ===================================================

    function _isSendTransceiverEnabledForChain(
        address transceiver,
        uint16 forChainId
    ) internal view override returns (bool) {
        uint64 bitmap = _getPerChainTransceiverBitmap(forChainId, SEND_TRANSCEIVER_BITMAP_SLOT);
        uint8 index = _getTransceiverInfosStorage()[transceiver].index;
        return (bitmap & uint64(1 << index)) > 0;
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

    function _checkTransceiversInvariants() internal view override {
        super._checkTransceiversInvariants();
        _validateTransceivers(SEND_ENABLED_CHAINS_SLOT, SEND_TRANSCEIVER_BITMAP_SLOT);
        _validateTransceivers(RECV_ENABLED_CHAINS_SLOT, RECV_TRANSCEIVER_BITMAP_SLOT);
    }

    function _validateTransceivers(bytes32 chainsTag, bytes32 bitmapTag) private view {
        uint16[] memory chains = _getEnabledChainsStorage(chainsTag);
        uint256 len = chains.length;
        for (uint256 idx = 0; idx < len;) {
            uint64 bitmap = _getPerChainTransceiverBitmap(chains[idx], bitmapTag);
            _validateTransceivers(bitmap);
            unchecked {
                ++idx;
            }
        }
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
        mapping(address => TransceiverInfo) storage transceiverInfos = _getTransceiverInfosStorage();
        address[] storage _enabledTransceivers = _getEnabledTransceiversStorage();
        uint256 len = _enabledTransceivers.length;
        for (uint256 idx = 0; (idx < len);) {
            address transceiverAddr = _enabledTransceivers[idx];
            if (transceiverInfos[transceiverAddr].index == index) {
                if (!transceiverInfos[transceiverAddr].registered) {
                    revert TransceiverNotRegistered(index, transceiverAddr);
                }

                if (!transceiverInfos[transceiverAddr].enabled) {
                    revert TransceiverNotEnabled(index, transceiverAddr);
                }
                // This index is good.
                return;
            }
            unchecked {
                ++idx;
            }
        }

        revert InvalidTransceiverIndex(index);
    }

    function _removeChain(bytes32 tag, uint16 forChainId) private {
        uint16[] storage chains = _getEnabledChainsStorage(tag);
        uint256 len = chains.length;
        for (uint256 idx = 0; (idx < len);) {
            if (chains[idx] == forChainId) {
                chains[idx] = chains[len - 1];
                chains.pop();
                return;
            }
            unchecked {
                ++idx;
            }
        }
    }

    function _addChainIfNeeded(bytes32 tag, uint16 forChainId) private {
        uint16[] storage chains = _getEnabledChainsStorage(tag);
        uint256 len = chains.length;
        for (uint256 idx = 0; (idx < len);) {
            if (chains[idx] == forChainId) {
                return;
            }
            unchecked {
                ++idx;
            }
        }
        chains.push(forChainId);
    }

    function _getEnabledChainsStorage(
        bytes32 tag
    ) internal pure returns (uint16[] storage $) {
        uint256 slot = uint256(tag);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }
}

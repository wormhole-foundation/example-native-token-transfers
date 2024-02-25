// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

/// @dev This contract is responsible for handling the registration of Transceivers.
abstract contract TransceiverRegistry {
    constructor() {
        _checkTransceiversInvariants();
    }

    /// @dev Information about registered transceivers.
    struct TransceiverInfo {
        // whether this transceiver is registered
        bool registered;
        // whether this transceiver is enabled
        bool enabled;
        uint8 index;
    }

    /// @dev Bitmap encoding the enabled transceivers.
    /// invariant: forall (i: uint8), enabledTransceiverBitmap & i == 1 <=> transceiverInfos[i].enabled
    struct _EnabledTransceiverBitmap {
        uint64 bitmap;
    }

    /// @dev Total number of registered transceivers. This number can only increase.
    /// invariant: numRegisteredTransceivers <= MAX_TRANSCEIVERS
    /// invariant: forall (i: uint8),
    ///   i < numRegisteredTransceivers <=> exists (a: address), transceiverInfos[a].index == i
    struct _NumTransceivers {
        uint8 registered;
        uint8 enabled;
    }

    uint8 constant MAX_TRANSCEIVERS = 64;

    error CallerNotTransceiver(address caller);
    error InvalidTransceiverZeroAddress();
    error DisabledTransceiver(address transceiver);
    error TooManyTransceivers();
    error NonRegisteredTransceiver(address transceiver);
    error TransceiverAlreadyEnabled(address transceiver);

    event TransceiverAdded(address transceiver);
    event TransceiverRemoved(address transceiver);

    modifier onlyTransceiver() {
        if (!_getTransceiverInfosStorage()[msg.sender].enabled) {
            revert CallerNotTransceiver(msg.sender);
        }
        _;
    }

    /// =============== STORAGE ===============================================

    bytes32 private constant TRANSCEIVER_INFOS_SLOT =
        bytes32(uint256(keccak256("ntt.transceiverInfos")) - 1);

    bytes32 private constant TRANSCEIVER_BITMAP_SLOT =
        bytes32(uint256(keccak256("ntt.transceiverBitmap")) - 1);

    bytes32 private constant ENABLED_TRANSCEIVERS_SLOT =
        bytes32(uint256(keccak256("ntt.enabledTransceivers")) - 1);

    bytes32 private constant REGISTERED_TRANSCEIVERS_SLOT =
        bytes32(uint256(keccak256("ntt.registeredTransceivers")) - 1);

    bytes32 private constant NUM_REGISTERED_TRANSCEIVERS_SLOT =
        bytes32(uint256(keccak256("ntt.numRegisteredTransceivers")) - 1);

    function _getTransceiverInfosStorage()
        internal
        pure
        returns (mapping(address => TransceiverInfo) storage $)
    {
        uint256 slot = uint256(TRANSCEIVER_INFOS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getEnabledTransceiversStorage() internal pure returns (address[] storage $) {
        uint256 slot = uint256(ENABLED_TRANSCEIVERS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getTransceiverBitmapStorage()
        private
        pure
        returns (_EnabledTransceiverBitmap storage $)
    {
        uint256 slot = uint256(TRANSCEIVER_BITMAP_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getRegisteredTransceiversStorage() internal pure returns (address[] storage $) {
        uint256 slot = uint256(REGISTERED_TRANSCEIVERS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getNumTransceiversStorage() internal pure returns (_NumTransceivers storage $) {
        uint256 slot = uint256(NUM_REGISTERED_TRANSCEIVERS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    /// =============== GETTERS/SETTERS ========================================

    function _setTransceiver(address transceiver) internal returns (uint8 index) {
        mapping(address => TransceiverInfo) storage transceiverInfos = _getTransceiverInfosStorage();
        _EnabledTransceiverBitmap storage _enabledTransceiverBitmap = _getTransceiverBitmapStorage();
        address[] storage _enabledTransceivers = _getEnabledTransceiversStorage();

        _NumTransceivers storage _numTransceivers = _getNumTransceiversStorage();

        if (transceiver == address(0)) {
            revert InvalidTransceiverZeroAddress();
        }

        if (_numTransceivers.registered >= MAX_TRANSCEIVERS) {
            revert TooManyTransceivers();
        }

        if (transceiverInfos[transceiver].registered) {
            transceiverInfos[transceiver].enabled = true;
        } else {
            transceiverInfos[transceiver] = TransceiverInfo({
                registered: true,
                enabled: true,
                index: _numTransceivers.registered
            });
            _numTransceivers.registered++;
            _getRegisteredTransceiversStorage().push(transceiver);
        }

        _enabledTransceivers.push(transceiver);
        _numTransceivers.enabled++;

        uint64 updatedEnabledTransceiverBitmap =
            _enabledTransceiverBitmap.bitmap | uint64(1 << transceiverInfos[transceiver].index);
        // ensure that this actually changed the bitmap
        if (updatedEnabledTransceiverBitmap == _enabledTransceiverBitmap.bitmap) {
            revert TransceiverAlreadyEnabled(transceiver);
        }
        _enabledTransceiverBitmap.bitmap = updatedEnabledTransceiverBitmap;

        emit TransceiverAdded(transceiver);

        _checkTransceiversInvariants();

        return transceiverInfos[transceiver].index;
    }

    function _removeTransceiver(address transceiver) internal {
        mapping(address => TransceiverInfo) storage transceiverInfos = _getTransceiverInfosStorage();
        _EnabledTransceiverBitmap storage _enabledTransceiverBitmap = _getTransceiverBitmapStorage();
        address[] storage _enabledTransceivers = _getEnabledTransceiversStorage();

        if (transceiver == address(0)) {
            revert InvalidTransceiverZeroAddress();
        }

        if (!transceiverInfos[transceiver].registered) {
            revert NonRegisteredTransceiver(transceiver);
        }

        if (!transceiverInfos[transceiver].enabled) {
            revert DisabledTransceiver(transceiver);
        }

        transceiverInfos[transceiver].enabled = false;
        _getNumTransceiversStorage().enabled--;

        uint64 updatedEnabledTransceiverBitmap =
            _enabledTransceiverBitmap.bitmap & uint64(~(1 << transceiverInfos[transceiver].index));
        // ensure that this actually changed the bitmap
        assert(updatedEnabledTransceiverBitmap < _enabledTransceiverBitmap.bitmap);
        _enabledTransceiverBitmap.bitmap = updatedEnabledTransceiverBitmap;

        bool removed = false;

        uint256 numEnabledTransceivers = _enabledTransceivers.length;
        for (uint256 i = 0; i < numEnabledTransceivers; i++) {
            if (_enabledTransceivers[i] == transceiver) {
                _enabledTransceivers[i] = _enabledTransceivers[numEnabledTransceivers - 1];
                _enabledTransceivers.pop();
                removed = true;
                break;
            }
        }
        assert(removed);

        emit TransceiverRemoved(transceiver);

        _checkTransceiversInvariants();
        // we call the invariant check on the transceiver here as well, since
        // the above check only iterates through the enabled transceivers.
        _checkTransceiverInvariants(transceiver);
    }

    function _getEnabledTransceiversBitmap() internal view virtual returns (uint64 bitmap) {
        return _getTransceiverBitmapStorage().bitmap;
    }

    /// @notice Returns the Transceiver contracts that have been registered via governance.
    function getTransceivers() external pure returns (address[] memory result) {
        result = _getEnabledTransceiversStorage();
    }

    /// ============== INVARIANTS =============================================

    /// @dev Check that the transceiver manager is in a valid state.
    /// Checking these invariants is somewhat costly, but we only need to do it
    /// when modifying the transceivers, which happens infrequently.
    function _checkTransceiversInvariants() internal view {
        _NumTransceivers storage _numTransceivers = _getNumTransceiversStorage();
        address[] storage _enabledTransceivers = _getEnabledTransceiversStorage();

        uint256 numTransceiversEnabled = _numTransceivers.enabled;
        assert(numTransceiversEnabled == _enabledTransceivers.length);

        for (uint256 i = 0; i < numTransceiversEnabled; i++) {
            _checkTransceiverInvariants(_enabledTransceivers[i]);
        }

        // invariant: each transceiver is only enabled once
        for (uint256 i = 0; i < numTransceiversEnabled; i++) {
            for (uint256 j = i + 1; j < numTransceiversEnabled; j++) {
                assert(_enabledTransceivers[i] != _enabledTransceivers[j]);
            }
        }

        // invariant: numRegisteredTransceivers <= MAX_TRANSCEIVERS
        assert(_numTransceivers.registered <= MAX_TRANSCEIVERS);
    }

    // @dev Check that the transceiver is in a valid state.
    function _checkTransceiverInvariants(address transceiver) private view {
        mapping(address => TransceiverInfo) storage transceiverInfos = _getTransceiverInfosStorage();
        _EnabledTransceiverBitmap storage _enabledTransceiverBitmap = _getTransceiverBitmapStorage();
        _NumTransceivers storage _numTransceivers = _getNumTransceiversStorage();
        address[] storage _enabledTransceivers = _getEnabledTransceiversStorage();

        TransceiverInfo memory transceiverInfo = transceiverInfos[transceiver];

        // if an transceiver is not registered, it should not be enabled
        assert(
            transceiverInfo.registered || (!transceiverInfo.enabled && transceiverInfo.index == 0)
        );

        bool transceiverInEnabledBitmap =
            (_enabledTransceiverBitmap.bitmap & uint64(1 << transceiverInfo.index)) != 0;
        bool transceiverEnabled = transceiverInfo.enabled;

        bool transceiverInEnabledTransceivers = false;

        for (uint256 i = 0; i < _numTransceivers.enabled; i++) {
            if (_enabledTransceivers[i] == transceiver) {
                transceiverInEnabledTransceivers = true;
                break;
            }
        }

        // invariant: transceiverInfos[transceiver].enabled
        //            <=> enabledTransceiverBitmap & (1 << transceiverInfos[transceiver].index) != 0
        assert(transceiverInEnabledBitmap == transceiverEnabled);

        // invariant: transceiverInfos[transceiver].enabled <=> transceiver in _enabledTransceivers
        assert(transceiverInEnabledTransceivers == transceiverEnabled);

        assert(transceiverInfo.index < _numTransceivers.registered);
    }
}

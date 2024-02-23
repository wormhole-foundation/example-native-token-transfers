// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

/// @dev This contract is responsible for handling the registration of Endpoints.
abstract contract EndpointRegistry {
    constructor() {
        _checkEndpointsInvariants();
    }

    /// @dev Information about registered endpoints.
    struct EndpointInfo {
        // whether this endpoint is registered
        bool registered;
        // whether this endpoint is enabled
        bool enabled;
        uint8 index;
    }

    /// @dev Bitmap encoding the enabled endpoints.
    /// invariant: forall (i: uint8), enabledEndpointBitmap & i == 1 <=> endpointInfos[i].enabled
    struct _EnabledEndpointBitmap {
        uint64 bitmap;
    }

    /// @dev Total number of registered endpoints. This number can only increase.
    /// invariant: numRegisteredEndpoints <= MAX_ENDPOINTS
    /// invariant: forall (i: uint8),
    ///   i < numRegisteredEndpoints <=> exists (a: address), endpointInfos[a].index == i
    struct _NumEndpoints {
        uint8 registered;
        uint8 enabled;
    }

    uint8 constant MAX_ENDPOINTS = 64;

    error CallerNotEndpoint(address caller);
    error InvalidEndpointZeroAddress();
    error DisabledEndpoint(address endpoint);
    error TooManyEndpoints();
    error NonRegisteredEndpoint(address endpoint);
    error EndpointAlreadyEnabled(address endpoint);

    event EndpointAdded(address endpoint);
    event EndpointRemoved(address endpoint);

    modifier onlyEndpoint() {
        if (!_getEndpointInfosStorage()[msg.sender].enabled) {
            revert CallerNotEndpoint(msg.sender);
        }
        _;
    }

    /// =============== STORAGE ===============================================

    bytes32 private constant ENDPOINT_INFOS_SLOT =
        bytes32(uint256(keccak256("ntt.endpointInfos")) - 1);

    bytes32 private constant ENDPOINT_BITMAP_SLOT =
        bytes32(uint256(keccak256("ntt.endpointBitmap")) - 1);

    bytes32 private constant ENABLED_ENDPOINTS_SLOT =
        bytes32(uint256(keccak256("ntt.enabledEndpoints")) - 1);

    bytes32 private constant REGISTERED_ENDPOINTS_SLOT =
        bytes32(uint256(keccak256("ntt.registeredEndpoints")) - 1);

    bytes32 private constant NUM_REGISTERED_ENDPOINTS_SLOT =
        bytes32(uint256(keccak256("ntt.numRegisteredEndpoints")) - 1);

    function _getEndpointInfosStorage()
        internal
        pure
        returns (mapping(address => EndpointInfo) storage $)
    {
        uint256 slot = uint256(ENDPOINT_INFOS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getEnabledEndpointsStorage() internal pure returns (address[] storage $) {
        uint256 slot = uint256(ENABLED_ENDPOINTS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getEndpointBitmapStorage() private pure returns (_EnabledEndpointBitmap storage $) {
        uint256 slot = uint256(ENDPOINT_BITMAP_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getRegisteredEndpointsStorage() internal pure returns (address[] storage $) {
        uint256 slot = uint256(REGISTERED_ENDPOINTS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getNumEndpointsStorage() internal pure returns (_NumEndpoints storage $) {
        uint256 slot = uint256(NUM_REGISTERED_ENDPOINTS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    /// =============== GETTERS/SETTERS ========================================

    function _setEndpoint(address endpoint) internal returns (uint8 index) {
        mapping(address => EndpointInfo) storage endpointInfos = _getEndpointInfosStorage();
        _EnabledEndpointBitmap storage _enabledEndpointBitmap = _getEndpointBitmapStorage();
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();

        _NumEndpoints storage _numEndpoints = _getNumEndpointsStorage();

        if (endpoint == address(0)) {
            revert InvalidEndpointZeroAddress();
        }

        if (_numEndpoints.registered >= MAX_ENDPOINTS) {
            revert TooManyEndpoints();
        }

        if (endpointInfos[endpoint].registered) {
            endpointInfos[endpoint].enabled = true;
        } else {
            endpointInfos[endpoint] =
                EndpointInfo({registered: true, enabled: true, index: _numEndpoints.registered});
            _numEndpoints.registered++;
            _getRegisteredEndpointsStorage().push(endpoint);
        }

        _enabledEndpoints.push(endpoint);
        _numEndpoints.enabled++;

        uint64 updatedEnabledEndpointBitmap =
            _enabledEndpointBitmap.bitmap | uint64(1 << endpointInfos[endpoint].index);
        // ensure that this actually changed the bitmap
        if (updatedEnabledEndpointBitmap == _enabledEndpointBitmap.bitmap) {
            revert EndpointAlreadyEnabled(endpoint);
        }
        _enabledEndpointBitmap.bitmap = updatedEnabledEndpointBitmap;

        emit EndpointAdded(endpoint);

        _checkEndpointsInvariants();

        return endpointInfos[endpoint].index;
    }

    function _removeEndpoint(address endpoint) internal {
        mapping(address => EndpointInfo) storage endpointInfos = _getEndpointInfosStorage();
        _EnabledEndpointBitmap storage _enabledEndpointBitmap = _getEndpointBitmapStorage();
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();

        if (endpoint == address(0)) {
            revert InvalidEndpointZeroAddress();
        }

        if (!endpointInfos[endpoint].registered) {
            revert NonRegisteredEndpoint(endpoint);
        }

        if (!endpointInfos[endpoint].enabled) {
            revert DisabledEndpoint(endpoint);
        }

        endpointInfos[endpoint].enabled = false;
        _getNumEndpointsStorage().enabled--;

        uint64 updatedEnabledEndpointBitmap =
            _enabledEndpointBitmap.bitmap & uint64(~(1 << endpointInfos[endpoint].index));
        // ensure that this actually changed the bitmap
        assert(updatedEnabledEndpointBitmap < _enabledEndpointBitmap.bitmap);
        _enabledEndpointBitmap.bitmap = updatedEnabledEndpointBitmap;

        bool removed = false;

        uint256 numEnabledEndpoints = _enabledEndpoints.length;
        for (uint256 i = 0; i < numEnabledEndpoints; i++) {
            if (_enabledEndpoints[i] == endpoint) {
                _enabledEndpoints[i] = _enabledEndpoints[numEnabledEndpoints - 1];
                _enabledEndpoints.pop();
                removed = true;
                break;
            }
        }
        assert(removed);

        emit EndpointRemoved(endpoint);

        _checkEndpointsInvariants();
        // we call the invariant check on the endpoint here as well, since
        // the above check only iterates through the enabled endpoints.
        _checkEndpointInvariants(endpoint);
    }

    function _getEnabledEndpointsBitmap() internal view virtual returns (uint64 bitmap) {
        return _getEndpointBitmapStorage().bitmap;
    }

    /// @notice Returns the Endpoint contracts that have been registered via governance.
    function getEndpoints() external pure returns (address[] memory result) {
        result = _getEnabledEndpointsStorage();
    }

    /// ============== INVARIANTS =============================================

    /// @dev Check that the endpoint manager is in a valid state.
    /// Checking these invariants is somewhat costly, but we only need to do it
    /// when modifying the endpoints, which happens infrequently.
    function _checkEndpointsInvariants() internal view {
        _NumEndpoints storage _numEndpoints = _getNumEndpointsStorage();
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();

        uint256 numEndpointsEnabled = _numEndpoints.enabled;
        assert(numEndpointsEnabled == _enabledEndpoints.length);

        for (uint256 i = 0; i < numEndpointsEnabled; i++) {
            _checkEndpointInvariants(_enabledEndpoints[i]);
        }

        // invariant: each endpoint is only enabled once
        for (uint256 i = 0; i < numEndpointsEnabled; i++) {
            for (uint256 j = i + 1; j < numEndpointsEnabled; j++) {
                assert(_enabledEndpoints[i] != _enabledEndpoints[j]);
            }
        }

        // invariant: numRegisteredEndpoints <= MAX_ENDPOINTS
        assert(_numEndpoints.registered <= MAX_ENDPOINTS);
    }

    // @dev Check that the endpoint is in a valid state.
    function _checkEndpointInvariants(address endpoint) private view {
        mapping(address => EndpointInfo) storage endpointInfos = _getEndpointInfosStorage();
        _EnabledEndpointBitmap storage _enabledEndpointBitmap = _getEndpointBitmapStorage();
        _NumEndpoints storage _numEndpoints = _getNumEndpointsStorage();
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();

        EndpointInfo memory endpointInfo = endpointInfos[endpoint];

        // if an endpoint is not registered, it should not be enabled
        assert(endpointInfo.registered || (!endpointInfo.enabled && endpointInfo.index == 0));

        bool endpointInEnabledBitmap =
            (_enabledEndpointBitmap.bitmap & uint64(1 << endpointInfo.index)) != 0;
        bool endpointEnabled = endpointInfo.enabled;

        bool endpointInEnabledEndpoints = false;

        for (uint256 i = 0; i < _numEndpoints.enabled; i++) {
            if (_enabledEndpoints[i] == endpoint) {
                endpointInEnabledEndpoints = true;
                break;
            }
        }

        // invariant: endpointInfos[endpoint].enabled
        //            <=> enabledEndpointBitmap & (1 << endpointInfos[endpoint].index) != 0
        assert(endpointInEnabledBitmap == endpointEnabled);

        // invariant: endpointInfos[endpoint].enabled <=> endpoint in _enabledEndpoints
        assert(endpointInEnabledEndpoints == endpointEnabled);

        assert(endpointInfo.index < _numEndpoints.registered);
    }
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

/// @dev This contract is responsible for handling the registration of Endpoints.
abstract contract EndpointRegistry {
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
    struct _NumRegisteredEndpoints {
        uint8 num;
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

    bytes32 public constant ENDPOINT_INFOS_SLOT =
        bytes32(uint256(keccak256("ntt.endpointInfos")) - 1);

    bytes32 public constant ENDPOINT_BITMAP_SLOT =
        bytes32(uint256(keccak256("ntt.endpointBitmap")) - 1);

    bytes32 public constant ENABLED_ENDPOINTS_SLOT =
        bytes32(uint256(keccak256("ntt.enabledEndpoints")) - 1);

    bytes32 public constant REGISTERED_ENDPOINTS_SLOT =
        bytes32(uint256(keccak256("ntt.registeredEndpoints")) - 1);

    bytes32 public constant NUM_REGISTERED_ENDPOINTS_SLOT =
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

    function _getNumRegisteredEndpointsStorage()
        internal
        pure
        returns (_NumRegisteredEndpoints storage $)
    {
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

        _NumRegisteredEndpoints storage _numRegisteredEndpoints =
            _getNumRegisteredEndpointsStorage();

        if (endpoint == address(0)) {
            revert InvalidEndpointZeroAddress();
        }

        if (_numRegisteredEndpoints.num >= MAX_ENDPOINTS) {
            revert TooManyEndpoints();
        }

        if (endpointInfos[endpoint].registered) {
            endpointInfos[endpoint].enabled = true;
        } else {
            endpointInfos[endpoint] =
                EndpointInfo({registered: true, enabled: true, index: _numRegisteredEndpoints.num});
            _numRegisteredEndpoints.num++;
            _getRegisteredEndpointsStorage().push(endpoint);
        }

        _enabledEndpoints.push(endpoint);

        uint64 updatedEnabledEndpointBitmap =
            _enabledEndpointBitmap.bitmap | uint64(1 << endpointInfos[endpoint].index);
        // ensure that this actually changed the bitmap
        if (updatedEnabledEndpointBitmap == _enabledEndpointBitmap.bitmap) {
            revert EndpointAlreadyEnabled(endpoint);
        }
        _enabledEndpointBitmap.bitmap = updatedEnabledEndpointBitmap;

        emit EndpointAdded(endpoint);

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

        uint64 updatedEnabledEndpointBitmap =
            _enabledEndpointBitmap.bitmap & uint64(~(1 << endpointInfos[endpoint].index));
        // ensure that this actually changed the bitmap
        assert(updatedEnabledEndpointBitmap < _enabledEndpointBitmap.bitmap);
        _enabledEndpointBitmap.bitmap = updatedEnabledEndpointBitmap;

        bool removed = false;

        for (uint256 i = 0; i < _enabledEndpoints.length; i++) {
            if (_enabledEndpoints[i] == endpoint) {
                _enabledEndpoints[i] = _enabledEndpoints[_enabledEndpoints.length - 1];
                _enabledEndpoints.pop();
                removed = true;
                break;
            }
        }
        assert(removed);

        emit EndpointRemoved(endpoint);
    }

    function _getEnabledEndpointsBitmap() internal view virtual returns (uint64 bitmap) {
        return _getEndpointBitmapStorage().bitmap;
    }

    /// @notice Returns the Endpoint contracts that have been registered via governance.
    function getEndpoints() external pure returns (address[] memory result) {
        result = _getEnabledEndpointsStorage();
    }
}

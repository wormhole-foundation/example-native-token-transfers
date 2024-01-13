// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./interfaces/IEndpointManagerStandalone.sol";
import "./interfaces/IEndpointStandalone.sol";
import "./EndpointManager.sol";

contract EndpointManagerStandalone is IEndpointManagerStandalone, EndpointManager {
    uint8 _threshold;

    // ========================= ENDPOINT REGISTRATION =========================

    // @dev Information about registered endpoints.
    struct EndpointInfo {
        // whether this endpoint is registered
        bool registered;
        // whether this endpoint is enabled
        bool enabled;
        uint8 index;
    }

    // @dev Information about registered endpoints.
    // This is the source of truth, we define a couple of derived fields below
    // for efficiency.
    mapping(address => EndpointInfo) public endpointInfos;

    // @dev List of enabled endpoints.
    // invariant: forall (a: address), endpointInfos[a].enabled <=> a in enabledEndpoints
    address[] _enabledEndpoints;

    // invariant: forall (i: uint8), enabledEndpointBitmap & i == 1 <=> endpointInfos[i].enabled
    uint64 _enabledEndpointBitmap;

    uint8 constant _MAX_ENDPOINTS = 64;

    // @dev Total number of registered endpoints. This number can only increase.
    // invariant: numRegisteredEndpoints <= MAX_ENDPOINTS
    // invariant: forall (i: uint8),
    //   i < numRegisteredEndpoints <=> exists (a: address), endpointInfos[a].index == i
    uint8 _numRegisteredEndpoints;

    // =========================================================================

    // @dev Information about attestations for a given message.
    struct AttestationInfo {
        // bitmap of endpoints that have attested to this message (NOTE: might contain disabled endpoints)
        uint64 attestedEndpoints;
        // whether this message has been executed
        bool executed;
    }

    // Maps are keyed by hash of EndpointManagerMessage.
    mapping(bytes32 => AttestationInfo) public managerMessageAttestations;

    modifier onlyEndpoint() {
        if (!endpointInfos[msg.sender].enabled) {
            revert CallerNotEndpoint(msg.sender);
        }
        _;
    }

    constructor(
        address token,
        bool isLockingMode,
        uint16 chainId
    ) EndpointManager(token, isLockingMode, chainId) {
        _checkEndpointsInvariants();
    }

    function quoteDeliveryPrice(uint16 recipientChain) public view override returns (uint256) {
        uint256 totalPriceQuote = 0;
        for (uint256 i = 0; i < _enabledEndpoints.length; i++) {
            uint256 endpointPriceQuote =
                IEndpointStandalone(_enabledEndpoints[i]).quoteDeliveryPrice(recipientChain);
            totalPriceQuote += endpointPriceQuote;
        }
        return totalPriceQuote;
    }

    function sendMessage(uint16 recipientChain, bytes memory payload) internal override {
        // call into endpoint contracts to send the message
        for (uint256 i = 0; i < _enabledEndpoints.length; i++) {
            uint256 endpointPriceQuote =
                IEndpointStandalone(_enabledEndpoints[i]).quoteDeliveryPrice(recipientChain);
            IEndpointStandalone(_enabledEndpoints[i]).sendMessage{value: endpointPriceQuote}(
                recipientChain, payload
            );
        }
    }

    function setSibling(
        uint16 siblingChainId,
        bytes32 siblingContract
    ) external override onlyOwner {
        // TODO -- how to properly do this??
        // this function should specify which endpoint the sibling is for
    }

    /// @dev Called by an Endpoint contract to deliver a verified attestation.
    ///      This function enforces attestation threshold and replay logic for messages.
    ///      Once all validations are complete, this function calls _executeMsg to execute the command specified by the message.
    function attestationReceived(bytes memory payload) external onlyEndpoint {
        bytes32 managerMessageHash = computeManagerMessageHash(payload);

        // set the attested flag for this endpoint.
        // TODO: this allows an endpoint to attest to a message multiple times.
        // This is fine, because attestation is idempotent (bitwise or 1), but
        // maybe we want to revert anyway?
        // TODO: factor out the bitmap logic into helper functions (or even a library)
        managerMessageAttestations[managerMessageHash].attestedEndpoints |=
            uint64(1 << endpointInfos[msg.sender].index);

        uint8 attestationCount = messageAttestations(managerMessageHash);

        // end early if the threshold hasn't been met.
        // otherwise, continue with execution for the message type.
        if (attestationCount < _threshold) {
            return;
        }

        _markMessageExecuted(managerMessageHash);

        return _executeMsg(payload);
    }

    // @dev Mark a message as executed.
    // This function will revert if the message has already been executed.
    function _markMessageExecuted(bytes32 digest) internal {
        // check if this message has already been executed
        if (managerMessageAttestations[digest].executed) {
            revert MessageAlreadyExecuted(digest);
        }

        // mark this message as executed
        managerMessageAttestations[digest].executed = true;
    }

    /// @notice Returns the number of Endpoints that must attest to a msgId for it to be considered valid and acted upon.
    function getThreshold() external view returns (uint8) {
        return _threshold;
    }

    function setThreshold(uint8 threshold) external onlyOwner {
        _threshold = threshold;
        _checkEndpointsInvariants();
    }

    /// @notice Returns the Endpoint contracts that have been registered via governance.
    function getEndpoints() external view returns (address[] memory) {
        return _enabledEndpoints;
    }

    function setEndpoint(address endpoint) external onlyOwner {
        if (endpoint == address(0)) {
            revert InvalidEndpointZeroAddress();
        }

        if (_numRegisteredEndpoints >= _MAX_ENDPOINTS) {
            revert TooManyEndpoints();
        }

        if (endpointInfos[endpoint].registered) {
            endpointInfos[endpoint].enabled = true;
        } else {
            endpointInfos[endpoint] =
                EndpointInfo({registered: true, enabled: true, index: _numRegisteredEndpoints});
            _numRegisteredEndpoints++;
        }

        _enabledEndpoints.push(endpoint);

        uint64 updatedEnabledEndpointBitmap =
            _enabledEndpointBitmap | uint64(1 << endpointInfos[endpoint].index);
        // ensure that this actually changed the bitmap
        assert(updatedEnabledEndpointBitmap > _enabledEndpointBitmap);
        _enabledEndpointBitmap = updatedEnabledEndpointBitmap;

        emit EndpointAdded(endpoint);

        _checkEndpointsInvariants();
    }

    function removeEndpoint(address endpoint) external onlyOwner {
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
            _enabledEndpointBitmap & uint64(~(1 << endpointInfos[endpoint].index));
        // ensure that this actually changed the bitmap
        assert(updatedEnabledEndpointBitmap < _enabledEndpointBitmap);
        _enabledEndpointBitmap = updatedEnabledEndpointBitmap;

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

        _checkEndpointsInvariants();
        // we call the invariant check on the endpoint here as well, since
        // the above check only iterates through the enabled endpoints.
        _checkEndpointInvariants(endpoint);
    }

    function computeManagerMessageHash(bytes memory payload) public pure returns (bytes32) {
        return keccak256(payload);
    }

    // @dev Count the number of attestations from enabled endpoints for a given message.
    function messageAttestations(bytes32 managerMessageHash) public view returns (uint8 count) {
        uint64 attestedEndpoints = managerMessageAttestations[managerMessageHash].attestedEndpoints;

        return countSetBits(attestedEndpoints & _enabledEndpointBitmap);
    }

    // @dev Count the number of set bits in a uint64
    function countSetBits(uint64 x) public pure returns (uint8 count) {
        while (x != 0) {
            x &= x - 1;
            count++;
        }

        return count;
    }

    // @dev Check that the endpoint manager is in a valid state.
    // Checking these invariants is somewhat costly, but we only need to do it
    // when modifying the endpoints, which happens infrequently.
    function _checkEndpointsInvariants() internal view {
        // TODO: add custom errors for each invariant

        for (uint256 i = 0; i < _enabledEndpoints.length; i++) {
            _checkEndpointInvariants(_enabledEndpoints[i]);
        }

        // invariant: each endpoint is only enabled once
        for (uint256 i = 0; i < _enabledEndpoints.length; i++) {
            for (uint256 j = i + 1; j < _enabledEndpoints.length; j++) {
                assert(_enabledEndpoints[i] != _enabledEndpoints[j]);
            }
        }

        // invariant: numRegisteredEndpoints <= MAX_ENDPOINTS
        assert(_numRegisteredEndpoints <= _MAX_ENDPOINTS);

        // invariant: threshold <= enabledEndpoints.length
        require(_threshold <= _enabledEndpoints.length, "threshold <= enabledEndpoints.length");
    }

    // @dev Check that the endpoint is in a valid state.
    function _checkEndpointInvariants(address endpoint) internal view {
        EndpointInfo memory endpointInfo = endpointInfos[endpoint];

        // if an endpoint is not registered, it should not be enabled
        assert(endpointInfo.registered || (!endpointInfo.enabled && endpointInfo.index == 0));

        bool endpointInEnabledBitmap =
            (_enabledEndpointBitmap & uint64(1 << endpointInfo.index)) != 0;
        bool endpointEnabled = endpointInfo.enabled;

        bool endpointInEnabledEndpoints = false;

        for (uint256 i = 0; i < _enabledEndpoints.length; i++) {
            if (_enabledEndpoints[i] == endpoint) {
                endpointInEnabledEndpoints = true;
                break;
            }
        }

        // invariant: endpointInfos[endpoint].enabled <=> enabledEndpointBitmap & (1 << endpointInfos[endpoint].index) != 0
        assert(endpointInEnabledBitmap == endpointEnabled);

        // invariant: endpointInfos[endpoint].enabled <=> endpoint in _enabledEndpoints
        assert(endpointInEnabledEndpoints == endpointEnabled);

        assert(endpointInfo.index < _numRegisteredEndpoints);
    }
}

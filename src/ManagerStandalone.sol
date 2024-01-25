// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./interfaces/IManagerStandalone.sol";
import "./interfaces/IEndpointStandalone.sol";
import "./Manager.sol";
import "./EndpointRegistry.sol";
import "./libraries/Implementation.sol";

contract ManagerStandalone is IManagerStandalone, Manager, Implementation {
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint256 rateLimitDuration
    ) Manager(token, mode, chainId, rateLimitDuration) {
        _checkThresholdInvariants();
    }

    function _initialize() internal override {
        __Manager_init();
        _checkThresholdInvariants();
        _checkEndpointsInvariants();
    }

    function _migrate() internal override {
        // TODO: document (migration code)
        _checkThresholdInvariants();
        _checkEndpointsInvariants();
    }

    function upgrade(address newImplementation) external onlyOwner {
        _upgrade(newImplementation);
    }

    struct _Threshold {
        uint8 num;
    }

    /// =============== STORAGE ===============================================

    bytes32 public constant THRESHOLD_SLOT = bytes32(uint256(keccak256("ntt.threshold")) - 1);

    function _getThresholdStorage() private pure returns (_Threshold storage $) {
        uint256 slot = uint256(THRESHOLD_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    /// =============== GETTERS/SETTERS ========================================

    function setThreshold(uint8 threshold) external onlyOwner {
        _Threshold storage _threshold = _getThresholdStorage();
        _threshold.num = threshold;
        _checkThresholdInvariants();
    }

    /// @notice Returns the number of Endpoints that must attest to a msgId for
    ///         it to be considered valid and acted upon.
    function getThreshold() public view returns (uint8) {
        _Threshold storage _threshold = _getThresholdStorage();
        return _threshold.num;
    }

    function setEndpoint(address endpoint) external onlyOwner {
        _setEndpoint(endpoint);

        _Threshold storage _threshold = _getThresholdStorage();
        // We increase the threshold here. This might not be what the user
        // wants, in which case they can call setThreshold() afterwards.
        // However, this is the most sensible default behaviour, since
        // this makes the system more secure in the event that the user forgets
        // to call setThreshold().
        _threshold.num += 1;
    }

    function removeEndpoint(address endpoint) external onlyOwner {
        _removeEndpoint(endpoint);

        _Threshold storage _threshold = _getThresholdStorage();
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();

        if (_enabledEndpoints.length < _threshold.num) {
            _threshold.num = uint8(_enabledEndpoints.length);
        }
    }

    function quoteDeliveryPrice(uint16 recipientChain) public view override returns (uint256) {
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();
        uint256 totalPriceQuote = 0;
        for (uint256 i = 0; i < _enabledEndpoints.length; i++) {
            uint256 endpointPriceQuote =
                IEndpointStandalone(_enabledEndpoints[i]).quoteDeliveryPrice(recipientChain);
            totalPriceQuote += endpointPriceQuote;
        }
        return totalPriceQuote;
    }

    function sendMessage(uint16 recipientChain, bytes memory payload) internal override {
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();
        // call into endpoint contracts to send the message
        for (uint256 i = 0; i < _enabledEndpoints.length; i++) {
            uint256 endpointPriceQuote =
                IEndpointStandalone(_enabledEndpoints[i]).quoteDeliveryPrice(recipientChain);
            IEndpointStandalone(_enabledEndpoints[i]).sendMessage{value: endpointPriceQuote}(
                recipientChain, payload
            );
        }
    }

    /// @dev Called by an Endpoint contract to deliver a verified attestation.
    ///      This function enforces attestation threshold and replay logic for messages.
    ///      Once all validations are complete, this function calls _executeMsg to execute the command specified by the message.
    function attestationReceived(EndpointStructs.ManagerMessage memory payload)
        external
        onlyEndpoint
    {
        bytes32 managerMessageHash = EndpointStructs.managerMessageDigest(payload);

        // set the attested flag for this endpoint.
        // TODO: this allows an endpoint to attest to a message multiple times.
        // This is fine, because attestation is idempotent (bitwise or 1), but
        // maybe we want to revert anyway?
        _setEndpointAttestedToMessage(managerMessageHash, msg.sender);

        if (isMessageApproved(managerMessageHash)) {
            _executeMsg(payload);
        }
    }

    // @dev Count the number of attestations from enabled endpoints for a given message.
    function messageAttestations(bytes32 digest) public view returns (uint8 count) {
        return countSetBits(_getMessageAttestations(digest));
    }

    function isMessageApproved(bytes32 digest) public view override returns (bool) {
        uint8 threshold = getThreshold();
        return messageAttestations(digest) >= threshold && threshold > 0;
    }

    // @dev Count the number of set bits in a uint64
    function countSetBits(uint64 x) public pure returns (uint8 count) {
        while (x != 0) {
            x &= x - 1;
            count++;
        }

        return count;
    }

    /// ============== INVARIANTS =============================================

    function _checkThresholdInvariants() internal view {
        _Threshold storage _threshold = _getThresholdStorage();
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();

        // invariant: threshold <= enabledEndpoints.length
        if (_threshold.num > _enabledEndpoints.length) {
            revert ThresholdTooHigh(_threshold.num, _enabledEndpoints.length);
        }

        if (_enabledEndpoints.length > 0) {
            if (_threshold.num == 0) {
                revert ZeroThreshold();
            }
        }
    }
}

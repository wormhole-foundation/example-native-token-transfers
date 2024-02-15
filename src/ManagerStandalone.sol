// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

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
        uint64 rateLimitDuration
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

    /// @dev When we add new immutables, this function should be updated
    function _checkImmutables() internal view override {
        assert(this.token() == token);
        assert(this.mode() == mode);
        assert(this.chainId() == chainId);
        assert(this.evmChainId() == evmChainId);
        assert(this.rateLimitDuration() == rateLimitDuration);
    }

    function upgrade(address newImplementation) external onlyOwner {
        _upgrade(newImplementation);
    }

    function upgradeEndpoint(address endpoint, address newImplementation) external onlyOwner {
        IEndpointStandalone(endpoint).upgrade(newImplementation);
    }

    /// @dev Transfer ownership of the Manager contract and all Endpoint contracts to a new owner.
    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
        // loop through all the registered endpoints and set the new owner of each endpoint to the newOwner
        address[] storage _registeredEndpoints = _getRegisteredEndpointsStorage();
        _checkRegisteredEndpointsInvariants();

        for (uint256 i = 0; i < _registeredEndpoints.length; i++) {
            IEndpointStandalone(_registeredEndpoints[i]).transferEndpointOwnership(newOwner);
        }
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
        uint8 oldThreshold = _threshold.num;

        _threshold.num = threshold;
        _checkThresholdInvariants();

        emit ThresholdChanged(oldThreshold, threshold);
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
        // We do not automatically increase the threshold here.
        // Automatically increasing the threshold can result in a scenario
        // where in-flight messages can't be redeemed.
        // For example: Assume there is 1 Endpoint and the threshold is 1.
        // If we were to add a new Endpoint, the threshold would increase to 2.
        // However, all messages that are either in-flight or that are sent on
        // a source chain that does not yet have 2 Endpoints will only have been
        // sent from a single endpoint, so they would never be able to get
        // redeemed.
        // Instead, we leave it up to the owner to manually update the threshold
        // after some period of time, ideally once all chains have the new Endpoint
        // and transfers that were sent via the old configuration are all complete.

        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();

        emit EndpointAdded(endpoint, _enabledEndpoints.length, _threshold.num);
    }

    function removeEndpoint(address endpoint) external onlyOwner {
        _removeEndpoint(endpoint);

        _Threshold storage _threshold = _getThresholdStorage();
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();

        if (_enabledEndpoints.length < _threshold.num) {
            _threshold.num = uint8(_enabledEndpoints.length);
        }

        emit EndpointRemoved(endpoint, _threshold.num);
    }

    function quoteDeliveryPrice(uint16 recipientChain)
        public
        view
        override
        returns (uint256[] memory)
    {
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();
        uint256[] memory priceQuotes = new uint256[](_enabledEndpoints.length);
        for (uint256 i = 0; i < _enabledEndpoints.length; i++) {
            uint256 endpointPriceQuote =
                IEndpointStandalone(_enabledEndpoints[i]).quoteDeliveryPrice(recipientChain);
            priceQuotes[i] = endpointPriceQuote;
        }
        return priceQuotes;
    }

    function _sendMessageToEndpoints(
        uint16 recipientChain,
        uint256[] memory priceQuotes,
        bytes memory payload
    ) internal override {
        address[] storage _enabledEndpoints = _getEnabledEndpointsStorage();
        // call into endpoint contracts to send the message
        for (uint256 i = 0; i < priceQuotes.length; i++) {
            IEndpointStandalone(_enabledEndpoints[i]).sendMessage{value: priceQuotes[i]}(
                recipientChain, payload
            );
        }
    }

    /// @dev Called by an Endpoint contract to deliver a verified attestation.
    ///      This function enforces attestation threshold and replay logic for messages.
    ///      Once all validations are complete, this function calls _executeMsg to execute the command specified by the message.
    function attestationReceived(
        uint16 sourceChainId,
        bytes32 sourceManagerAddress,
        EndpointStructs.ManagerMessage memory payload
    ) external onlyEndpoint {
        _verifySibling(sourceChainId, sourceManagerAddress);

        bytes32 managerMessageHash = EndpointStructs.managerMessageDigest(sourceChainId, payload);

        // set the attested flag for this endpoint.
        // TODO: this allows an endpoint to attest to a message multiple times.
        // This is fine, because attestation is idempotent (bitwise or 1), but
        // maybe we want to revert anyway?
        _setEndpointAttestedToMessage(managerMessageHash, msg.sender);

        if (isMessageApproved(managerMessageHash)) {
            _executeMsg(sourceChainId, sourceManagerAddress, payload);
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

    function _checkRegisteredEndpointsInvariants() internal view {
        if (_getRegisteredEndpointsStorage().length != _getNumRegisteredEndpointsStorage().num) {
            revert RetrievedIncorrectRegisteredEndpoints(
                _getRegisteredEndpointsStorage().length, _getNumRegisteredEndpointsStorage().num
            );
        }
    }

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

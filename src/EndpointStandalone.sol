// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./Endpoint.sol";
import "./interfaces/IManagerStandalone.sol";
import "./interfaces/IEndpointStandalone.sol";
import "./libraries/Implementation.sol";
import "./libraries/external/ReentrancyGuardUpgradeable.sol";

abstract contract EndpointStandalone is
    IEndpointStandalone,
    Endpoint,
    Implementation,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant ENDPOINT_MANAGER_SLOT =
        bytes32(uint256(keccak256("endpoint.manager")) - 1);

    /// @dev updating bridgeManager requires a new Endpoint deployment.
    /// Projects should implement their own governance to remove the old Endpoint contract address and then add the new one.
    function _getEndpointManagerStorage() internal pure returns (_Address storage $) {
        uint256 slot = uint256(ENDPOINT_MANAGER_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    constructor(address manager) {
        _getEndpointManagerStorage().addr = manager;
    }

    modifier onlyManager() {
        if (msg.sender != getEndpointManager()) {
            revert CallerNotManager(msg.sender);
        }
        _;
    }

    function _initialize() internal override {
        // TODO: check if it's safe to not initialise reentrancy guard
        __ReentrancyGuard_init();
    }

    function _migrate() internal override {}

    function upgrade(address newImplementation) external onlyManager {
        _upgrade(newImplementation);
    }

    /// @notice Called by the BridgeManager contract to send a cross-chain message.
    function sendMessage(
        uint16 recipientChain,
        bytes memory payload
    ) external payable nonReentrant onlyManager {
        _sendMessage(recipientChain, payload);
    }

    function quoteDeliveryPrice(uint16 targetChain) external view override returns (uint256) {
        return _quoteDeliveryPrice(targetChain);
    }

    function _deliverToManager(EndpointStructs.ManagerMessage memory payload) internal override {
        // forward the VAA payload to the endpoint manager contract
        IManagerStandalone(getEndpointManager()).attestationReceived(payload);
    }

    function getEndpointManager() public view returns (address) {
        return _getEndpointManagerStorage().addr;
    }
}

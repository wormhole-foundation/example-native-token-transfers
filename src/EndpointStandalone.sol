// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

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
    /// @dev updating bridgeManager requires a new Endpoint deployment.
    /// Projects should implement their own governance to remove the old Endpoint contract address and then add the new one.
    address public immutable manager;

    constructor(address _manager) {
        manager = _manager;
    }

    modifier onlyManager() {
        if (msg.sender != manager) {
            revert CallerNotManager(msg.sender);
        }
        _;
    }

    function _initialize() internal override {
        // TODO: check if it's safe to not initialise reentrancy guard
        __ReentrancyGuard_init();
        // TODO: msg.sender may not be the right address
        __PausedOwnable_init(msg.sender, msg.sender);
    }

    function _migrate() internal virtual override {}

    /// @dev When we add new immutables, this function should be updated
    function _checkImmutables() internal view override {
        assert(this.manager() == manager);
    }

    function upgrade(address newImplementation) external onlyManager {
        _upgrade(newImplementation);
    }

    /// @notice pause the endpoint
    /// TODO: add in pauser role
    function pauseEndpoint() external virtual {}

    /// @notice Called by the BridgeManager contract to send a cross-chain message.
    function sendMessage(
        uint16 recipientChain,
        bytes memory managerMessage
    ) external payable nonReentrant onlyManager {
        _sendMessage(recipientChain, msg.value, managerMessage);
    }

    function quoteDeliveryPrice(uint16 targetChain) external view override returns (uint256) {
        return _quoteDeliveryPrice(targetChain);
    }

    function _deliverToManager(
        uint16 sourceChainId,
        bytes32 sourceManagerAddress,
        EndpointStructs.ManagerMessage memory payload
    ) internal override {
        // forward the VAA payload to the endpoint manager contract
        IManagerStandalone(manager).attestationReceived(
            sourceChainId, sourceManagerAddress, payload
        );
    }
}

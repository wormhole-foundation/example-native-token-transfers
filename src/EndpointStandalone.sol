// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./Endpoint.sol";
import "./interfaces/IManagerStandalone.sol";
import "./interfaces/IEndpointStandalone.sol";
import "./libraries/Implementation.sol";
import "./libraries/external/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IManager.sol";
import "./interfaces/IOwnableUpgradeable.sol";

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

    /// @dev Returns the owner of the manager contract
    function getManagerOwner() public view returns (address) {
        return IOwnableUpgradeable(manager).owner();
    }

    /// @dev transfer the ownership of the endpoint to a new address
    /// the manager should be able to transfer endpoint ownership
    function transferEndpointOwnership(address newOwner) external onlyManager {
        _transferOwnership(newOwner);
    }

    function _initialize() internal override {
        // TODO: check if it's safe to not initialise reentrancy guard
        __ReentrancyGuard_init();
        // owner of the endpoint is set to the owner of the manager
        // TODO: check if this needs to be msg.sender
        __PausedOwnable_init(msg.sender, getManagerOwner());
    }

    function _migrate() internal virtual override {}

    /// @dev When we add new immutables, this function should be updated
    function _checkImmutables() internal view override {
        assert(this.manager() == manager);
    }

    function upgrade(address newImplementation) external onlyOwner {
        _upgrade(newImplementation);
    }

    /// @notice pause the endpoint
    /// TODO: add in pauser role
    function pauseEndpoint() external virtual {}

    function renouncePauser() external virtual {}

    /// @notice Called by the BridgeManager contract to send a cross-chain message.
    function sendMessage(
        uint16 recipientChain,
        EndpointStructs.EndpointInstruction memory instruction,
        bytes memory managerMessage
    ) external payable nonReentrant onlyManager {
        _sendMessage(recipientChain, msg.value, msg.sender, instruction, managerMessage);
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

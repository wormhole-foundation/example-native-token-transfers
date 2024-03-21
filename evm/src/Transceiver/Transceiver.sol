// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/Utils.sol";

import "../libraries/TransceiverStructs.sol";
import "../libraries/PausableOwnable.sol";
import "../libraries/external/ReentrancyGuardUpgradeable.sol";
import "../libraries/Implementation.sol";

import "../interfaces/INttManager.sol";
import "../interfaces/ITransceiver.sol";

/// @title Transceiver
/// @author Wormhole Project Contributors.
/// @notice This contract is a base contract for Transceivers.
/// @dev The Transceiver provides basic functionality for transmitting / receiving NTT messages.
///      The contract supports pausing via an admin or owner and is upgradable.
///
/// @dev The interface for receiving messages is not enforced by this contract.
///      Instead, inheriting contracts should implement their own receiving logic,
///      based on the verification model and serde logic associated with message handling.
abstract contract Transceiver is
    ITransceiver,
    PausableOwnable,
    ReentrancyGuardUpgradeable,
    Implementation
{
    /// @dev updating bridgeNttManager requires a new Transceiver deployment.
    /// Projects should implement their own governance to remove the old Transceiver
    /// contract address and then add the new one.
    address public immutable nttManager;
    address public immutable nttManagerToken;
    address immutable deployer;

    constructor(address _nttManager) {
        nttManager = _nttManager;
        nttManagerToken = INttManager(nttManager).token();
        deployer = msg.sender;
    }

    /// =============== MODIFIERS ===============================================

    modifier onlyNttManager() {
        if (msg.sender != nttManager) {
            revert CallerNotNttManager(msg.sender);
        }
        _;
    }

    /// =============== ADMIN ===============================================

    function _initialize() internal virtual override {
        // check if the owner is the deployer of this contract
        if (msg.sender != deployer) {
            revert UnexpectedDeployer(deployer, msg.sender);
        }

        __ReentrancyGuard_init();
        // owner of the transceiver is set to the owner of the nttManager
        __PausedOwnable_init(msg.sender, getNttManagerOwner());
    }

    /// @dev transfer the ownership of the transceiver to a new address
    /// the nttManager should be able to update transceiver ownership.
    function transferTransceiverOwnership(address newOwner) external onlyNttManager {
        _transferOwnership(newOwner);
    }

    function upgrade(address newImplementation) external onlyOwner {
        _upgrade(newImplementation);
    }

    function _migrate() internal virtual override {}

    // @define This method checks that the the referecnes to the nttManager and its corresponding function
    // are correct When new immutable variables are added, this function should be updated.
    function _checkImmutables() internal view virtual override {
        assert(this.nttManager() == nttManager);
        assert(this.nttManagerToken() == nttManagerToken);
    }

    /// =============== GETTERS & SETTERS ===============================================

    function getNttManagerOwner() public view returns (address) {
        return IOwnableUpgradeable(nttManager).owner();
    }

    function getNttManagerToken() public view virtual returns (address) {
        return nttManagerToken;
    }

    /// =============== TRANSCEIVING LOGIC ===============================================

    /// @inheritdoc ITransceiver
    function quoteDeliveryPrice(
        uint16 targetChain,
        TransceiverStructs.TransceiverInstruction memory instruction,
        uint256 managerExecutionCost
    ) external view returns (uint256) {
        return _quoteDeliveryPrice(targetChain, instruction, managerExecutionCost);
    }

    /// @inheritdoc ITransceiver
    function sendMessage(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction memory instruction,
        bytes memory ManagerMessage,
        bytes32 recipientNttManagerAddress,
        uint256 managerExecutionCost
    ) external payable nonReentrant onlyNttManager {
        _sendMessage(
            recipientChain,
            msg.value,
            managerExecutionCost,
            msg.sender,
            recipientNttManagerAddress,
            instruction,
            ManagerMessage
        );
    }

    /// ============================= INTERNAL =========================================

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        uint256 managerExecutionCost,
        address caller,
        bytes32 recipientNttManagerAddress,
        TransceiverStructs.TransceiverInstruction memory transceiverInstruction,
        bytes memory ManagerMessage
    ) internal virtual;

    // @define This method is called by the BridgeNttManager contract to send a cross-chain message.
    // @reverts if:
    //     - `recipientNttManagerAddress` does not match the address of this manager contract
    function _deliverToNttManager(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        bytes32 recipientNttManagerAddress,
        TransceiverStructs.ManagerMessage memory payload
    ) internal virtual {
        if (recipientNttManagerAddress != toWormholeFormat(nttManager)) {
            revert UnexpectedRecipientNttManagerAddress(
                toWormholeFormat(nttManager), recipientNttManagerAddress
            );
        }
        INttManager(nttManager).attestationReceived(sourceChainId, sourceNttManagerAddress, payload);
    }

    function _quoteDeliveryPrice(
        uint16 targetChain,
        TransceiverStructs.TransceiverInstruction memory transceiverInstruction,
        uint256 managerExecutionCost
    ) internal view virtual returns (uint256);
}

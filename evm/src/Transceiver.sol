// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./libraries/TransceiverStructs.sol";
import "./libraries/PausableOwnable.sol";
import "./interfaces/IManager.sol";
import "./interfaces/ITransceiver.sol";
import "./libraries/external/ReentrancyGuardUpgradeable.sol";
import "./libraries/Implementation.sol";
import "wormhole-solidity-sdk/Utils.sol";

abstract contract Transceiver is
    ITransceiver,
    PausableOwnable,
    ReentrancyGuardUpgradeable,
    Implementation
{
    /// @dev updating bridgeManager requires a new Transceiver deployment.
    /// Projects should implement their own governance to remove the old Transceiver contract address and then add the new one.
    address public immutable manager;
    address public immutable managerToken;

    constructor(address _manager) {
        manager = _manager;
        managerToken = IManager(manager).token();
    }

    /// =============== MODIFIERS ===============================================

    modifier onlyManager() {
        if (msg.sender != manager) {
            revert CallerNotManager(msg.sender);
        }
        _;
    }

    /// =============== ADMIN ===============================================

    function _initialize() internal virtual override {
        __ReentrancyGuard_init();
        // owner of the transceiver is set to the owner of the manager
        __PausedOwnable_init(msg.sender, getManagerOwner());
    }

    /// @dev transfer the ownership of the transceiver to a new address
    /// the manager should be able to update transceiver ownership.
    function transferTransceiverOwnership(address newOwner) external onlyManager {
        _transferOwnership(newOwner);
    }

    /// @dev pause the transceiver.
    function _pauseTransceiver() internal {
        _pause();
    }

    function upgrade(address newImplementation) external onlyOwner {
        _upgrade(newImplementation);
    }

    function _migrate() internal virtual override {}

    /// @dev This method checks that the the referecnes to the manager and its corresponding function are correct
    /// When new immutable variables are added, this function should be updated.
    function _checkImmutables() internal view override {
        assert(this.manager() == manager);
        assert(this.managerToken() == managerToken);
    }

    /// =============== GETTERS & SETTERS ===============================================

    function getManagerOwner() public view returns (address) {
        return IOwnableUpgradeable(manager).owner();
    }

    function getManagerToken() public view virtual returns (address) {
        return managerToken;
    }

    /// =============== TRANSCEIVING LOGIC ===============================================
    /**
     *   @dev send a message to another chain.
     *   @param recipientChain The chain id of the recipient.
     *   @param instruction An additional Instruction provided by the Transceiver to be
     *          executed on the recipient chain.
     *   @param managerMessage A message to be sent to the manager on the recipient chain.
     */
    function sendMessage(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction memory instruction,
        bytes memory managerMessage,
        bytes32 recipientManagerAddress
    ) external payable nonReentrant onlyManager {
        _sendMessage(
            recipientChain,
            msg.value,
            msg.sender,
            recipientManagerAddress,
            instruction,
            managerMessage
        );
    }

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        bytes32 recipientManagerAddress,
        TransceiverStructs.TransceiverInstruction memory transceiverInstruction,
        bytes memory managerMessage
    ) internal virtual;

    // @dev      This method is called by the BridgeManager contract to send a cross-chain message.
    //           Forwards the VAA payload to the transceiver manager contract.
    // @param    sourceChainId The chain id of the sender.
    // @param    sourceManagerAddress The address of the sender's manager contract.
    // @param    payload The VAA payload.
    function _deliverToManager(
        uint16 sourceChainId,
        bytes32 sourceManagerAddress,
        bytes32 recipientManagerAddress,
        TransceiverStructs.ManagerMessage memory payload
    ) internal virtual {
        if (recipientManagerAddress != toWormholeFormat(manager)) {
            revert UnexpectedRecipientManagerAddress(
                toWormholeFormat(manager), recipientManagerAddress
            );
        }
        IManager(manager).attestationReceived(sourceChainId, sourceManagerAddress, payload);
    }

    function quoteDeliveryPrice(
        uint16 targetChain,
        TransceiverStructs.TransceiverInstruction memory instruction
    ) external view returns (uint256) {
        return _quoteDeliveryPrice(targetChain, instruction);
    }

    function _quoteDeliveryPrice(
        uint16 targetChain,
        TransceiverStructs.TransceiverInstruction memory transceiverInstruction
    ) internal view virtual returns (uint256);
}

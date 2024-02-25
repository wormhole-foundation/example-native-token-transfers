// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/Utils.sol";

import "../libraries/TransceiverStructs.sol";
import "../libraries/PausableOwnable.sol";
import "../libraries/external/ReentrancyGuardUpgradeable.sol";
import "../libraries/Implementation.sol";

import "../interfaces/INttManager.sol";
import "../interfaces/ITransceiver.sol";

abstract contract Transceiver is
    ITransceiver,
    PausableOwnable,
    ReentrancyGuardUpgradeable,
    Implementation
{
    /// @dev updating bridgeNttManager requires a new Transceiver deployment.
    /// Projects should implement their own governance to remove the old Transceiver contract address and then add the new one.
    address public immutable nttManager;
    address public immutable nttManagerToken;

    constructor(address _nttManager) {
        nttManager = _nttManager;
        nttManagerToken = INttManager(nttManager).token();
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
        __ReentrancyGuard_init();
        // owner of the transceiver is set to the owner of the nttManager
        __PausedOwnable_init(msg.sender, getNttManagerOwner());
    }

    /// @dev transfer the ownership of the transceiver to a new address
    /// the nttManager should be able to update transceiver ownership.
    function transferTransceiverOwnership(address newOwner) external onlyNttManager {
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

    /// @dev This method checks that the the referecnes to the nttManager and its corresponding function are correct
    /// When new immutable variables are added, this function should be updated.
    function _checkImmutables() internal view override {
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
    /**
     *   @dev send a message to another chain.
     *   @param recipientChain The chain id of the recipient.
     *   @param instruction An additional Instruction provided by the Transceiver to be
     *          executed on the recipient chain.
     *   @param nttManagerMessage A message to be sent to the nttManager on the recipient chain.
     */
    function sendMessage(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction memory instruction,
        bytes memory nttManagerMessage,
        bytes32 recipientNttManagerAddress
    ) external payable nonReentrant onlyNttManager {
        _sendMessage(
            recipientChain,
            msg.value,
            msg.sender,
            recipientNttManagerAddress,
            instruction,
            nttManagerMessage
        );
    }

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        bytes32 recipientNttManagerAddress,
        TransceiverStructs.TransceiverInstruction memory transceiverInstruction,
        bytes memory nttManagerMessage
    ) internal virtual;

    // @dev      This method is called by the BridgeNttManager contract to send a cross-chain message.
    //           Forwards the VAA payload to the transceiver nttManager contract.
    // @param    sourceChainId The chain id of the sender.
    // @param    sourceNttManagerAddress The address of the sender's nttManager contract.
    // @param    payload The VAA payload.
    function _deliverToNttManager(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        bytes32 recipientNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory payload
    ) internal virtual {
        if (recipientNttManagerAddress != toWormholeFormat(nttManager)) {
            revert UnexpectedRecipientNttManagerAddress(
                toWormholeFormat(nttManager), recipientNttManagerAddress
            );
        }
        INttManager(nttManager).attestationReceived(sourceChainId, sourceNttManagerAddress, payload);
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

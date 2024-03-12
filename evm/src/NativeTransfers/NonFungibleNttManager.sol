// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "../libraries/TransceiverHelpers.sol";

import "../interfaces/ITransceiver.sol";
import "../interfaces/INonFungibleNttManager.sol";
import "../interfaces/INonFungibleNttToken.sol";

import {ManagerBase} from "./shared/ManagerBase.sol";

contract NonFungibleNttManager is INonFungibleNttManager, ManagerBase {
    using BytesParsing for bytes;

    // =============== Immutables ============================================================

    uint8 constant MAX_BATCH_SIZE = 50;

    // =============== Setup =================================================================

    constructor(address _token, Mode _mode, uint16 _chainId) ManagerBase(_token, _mode, _chainId) {}

    function __NonFungibleNttManager_init() internal onlyInitializing {
        // check if the owner is the deployer of this contract
        if (msg.sender != deployer) {
            revert UnexpectedDeployer(deployer, msg.sender);
        }
        __PausedOwnable_init(msg.sender, msg.sender);
        __ReentrancyGuard_init();
    }

    function _initialize() internal virtual override {
        __NonFungibleNttManager_init();
        _checkThresholdInvariants();
        _checkTransceiversInvariants();
    }

    // =============== Storage ==============================================================

    bytes32 private constant PEERS_SLOT = bytes32(uint256(keccak256("nonFungibleNtt.peers")) - 1);

    // =============== Storage Getters/Setters ==============================================

    function _getPeersStorage()
        internal
        pure
        returns (mapping(uint16 => NonFungibleNttManagerPeer) storage $)
    {
        uint256 slot = uint256(PEERS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    // =============== Public Getters ========================================================

    function getPeer(uint16 chainId_) external view returns (NonFungibleNttManagerPeer memory) {
        return _getPeersStorage()[chainId_];
    }

    function getMaxBatchSize() external view returns (uint8) {
        return MAX_BATCH_SIZE;
    }

    // =============== Admin ==============================================================

    function setPeer(uint16 peerChainId, bytes32 peerContract) public onlyOwner {
        if (peerChainId == 0) {
            revert InvalidPeerChainIdZero();
        }
        if (peerContract == bytes32(0)) {
            revert InvalidPeerZeroAddress();
        }

        NonFungibleNttManagerPeer memory oldPeer = _getPeersStorage()[peerChainId];

        _getPeersStorage()[peerChainId].peerAddress = peerContract;

        emit PeerUpdated(peerChainId, oldPeer.peerAddress, peerContract);
    }

    // =============== External Interface ==================================================

    function transfer(
        uint256[] memory tokenIds,
        uint16 recipientChain,
        bytes32 recipient,
        bytes memory transceiverInstructions
    ) external payable nonReentrant whenNotPaused returns (uint64) {
        return _transfer(tokenIds, recipientChain, recipient, transceiverInstructions);
    }

    function attestationReceived(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.ManagerMessage memory payload
    ) external onlyTransceiver {
        _verifyPeer(sourceChainId, sourceNttManagerAddress);

        // Compute manager message digest and record transceiver attestation.
        bytes32 ManagerMessageHash = _recordTransceiverAttestation(sourceChainId, payload);

        if (isMessageApproved(ManagerMessageHash)) {
            executeMsg(sourceChainId, sourceNttManagerAddress, payload);
        }
    }

    function executeMsg(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.ManagerMessage memory message
    ) public {
        // verify chain has not forked
        checkFork(evmChainId);

        (bytes32 digest, bool alreadyExecuted) =
            _isMessageExecuted(sourceChainId, sourceNttManagerAddress, message);

        if (alreadyExecuted) {
            return;
        }

        TransceiverStructs.NonFungibleNativeTokenTransfer memory nft =
            TransceiverStructs.parseNonFungibleNativeTokenTransfer(message.payload);

        // verify that the destination chain is valid
        if (nft.toChain != chainId) {
            revert InvalidTargetChain(nft.toChain, chainId);
        }

        emit TransferRedeemed(digest);

        if (mode == Mode.BURNING) {
            _mintTokens(nft.tokenIds, fromWormholeFormat(nft.to));
        } else if (mode == Mode.LOCKING) {
            _unlockTokens(nft.tokenIds, fromWormholeFormat(nft.to));
        } else {
            revert InvalidMode(uint8(mode));
        }
    }

    function onERC721Received(
        address operator,
        address,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        if (operator != address(this)) {
            revert InvalidOperator(operator, address(this));
        }
        return type(IERC721Receiver).interfaceId;
    }

    // ==================== Internal Business Logic =========================================

    function _transfer(
        uint256[] memory tokenIds,
        uint16 recipientChain,
        bytes32 recipient,
        bytes memory transceiverInstructions
    ) internal returns (uint64) {
        if (tokenIds.length == 0) {
            revert ZeroTokenIds();
        }

        if (tokenIds.length > MAX_BATCH_SIZE) {
            revert ExceedsMaxBatchSize(tokenIds.length, MAX_BATCH_SIZE);
        }

        if (recipient == bytes32(0)) {
            revert InvalidRecipient();
        }

        // NOTE: Burn or lock tokens depending on the Mode. There are no validation checks
        // performed on the array of tokenIds. It is the caller's responsibility to ensure
        // that the tokenIds are unique and approved. Otherwise, the call to burn or transfer
        // the same tokenId will fail.
        if (mode == Mode.BURNING) {
            _burnTokens(tokenIds);
        } else if (mode == Mode.LOCKING) {
            _lockTokens(tokenIds);
        } else {
            revert InvalidMode(uint8(mode));
        }

        // Fetch quotes and prepare for transfer.
        (
            address[] memory enabledTransceivers,
            TransceiverStructs.TransceiverInstruction[] memory instructions,
            uint256[] memory priceQuotes,
            uint256 totalPriceQuote
        ) = _prepareForTransfer(recipientChain, transceiverInstructions);

        uint64 sequence = _useMessageSequence();

        TransceiverStructs.NonFungibleNativeTokenTransfer memory nft =
            TransceiverStructs.NonFungibleNativeTokenTransfer(recipient, recipientChain, tokenIds);

        // construct the ManagerMessage payload
        bytes memory encodedNttManagerPayload = TransceiverStructs.encodeManagerMessage(
            TransceiverStructs.ManagerMessage(
                bytes32(uint256(sequence)),
                toWormholeFormat(msg.sender),
                TransceiverStructs.encodeNonFungibleNativeTokenTransfer(nft)
            )
        );

        // Cache and verify peer.
        bytes32 destinationPeer = _getPeersStorage()[recipientChain].peerAddress;
        if (destinationPeer == bytes32(0)) {
            revert InvalidPeer(recipientChain, destinationPeer);
        }

        // send the message
        _sendMessageToTransceivers(
            recipientChain,
            destinationPeer,
            priceQuotes,
            instructions,
            enabledTransceivers,
            encodedNttManagerPayload
        );

        emit TransferSent(
            recipient, uint16(tokenIds.length), totalPriceQuote, recipientChain, sequence
        );

        return sequence;
    }

    // ==================== Internal Helpers ===============================================

    function _lockTokens(uint256[] memory tokenIds) internal {
        uint256 len = tokenIds.length;

        for (uint256 i = 0; i < len; ++i) {
            IERC721(token).safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }
    }

    function _unlockTokens(uint256[] memory tokenIds, address recipient) internal {
        uint256 len = tokenIds.length;

        for (uint256 i = 0; i < len; ++i) {
            IERC721(token).safeTransferFrom(address(this), recipient, tokenIds[i]);
        }
    }

    function _burnTokens(uint256[] memory tokenIds) internal {
        uint256 len = tokenIds.length;

        for (uint256 i = 0; i < len; ++i) {
            ERC721Burnable(token).burn(tokenIds[i]);
        }
    }

    function _mintTokens(uint256[] memory tokenIds, address recipient) internal {
        uint256 len = tokenIds.length;

        for (uint256 i = 0; i < len; ++i) {
            INonFungibleNttToken(token).mint(recipient, tokenIds[i]);
        }
    }

    /// @dev Verify that the peer address saved for `sourceChainId` matches the `peerAddress`.
    function _verifyPeer(uint16 sourceChainId, bytes32 peerAddress) internal view {
        if (_getPeersStorage()[sourceChainId].peerAddress != peerAddress) {
            revert InvalidPeer(sourceChainId, peerAddress);
        }
    }
}

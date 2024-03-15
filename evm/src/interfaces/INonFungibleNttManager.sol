// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TrimmedAmount.sol";
import "../libraries/TransceiverStructs.sol";

import "./IManagerBase.sol";

interface INonFungibleNttManager is IManagerBase {
    /// @dev The peer on another chain.
    struct NonFungibleNttManagerPeer {
        bytes32 peerAddress;
    }

    /// @notice Emitted when the peer contract is updated.
    /// @dev Topic0
    ///      0x1456404e7f41f35c3daac941bb50bad417a66275c3040061b4287d787719599d.
    /// @param chainId_ The chain ID of the peer contract.
    /// @param oldPeerContract The old peer contract address.
    /// @param peerContract The new peer contract address.
    event PeerUpdated(uint16 indexed chainId_, bytes32 oldPeerContract, bytes32 peerContract);

    /// @notice Emitted when a message is sent from the nttManager.
    /// @param recipient The recipient of the message.
    /// @param batchSize The number of NFTs transferred.
    /// @param fee The amount of ether sent along with the tx to cover the delivery fee.
    /// @param recipientChain The chain ID of the recipient.
    /// @param msgSequence The unique sequence ID of the message.
    event TransferSent(
        bytes32 recipient, uint16 batchSize, uint256 fee, uint16 recipientChain, uint64 msgSequence
    );

    /// @notice Emitted when a transfer has been redeemed
    ///         (either minted or unlocked on the recipient chain).
    /// @dev Topic0
    ///      0x504e6efe18ab9eed10dc6501a417f5b12a2f7f2b1593aed9b89f9bce3cf29a91.
    /// @param digest The digest of the message.
    event TransferRedeemed(bytes32 indexed digest);

    /// @notice The caller is not the deployer.
    error UnexpectedDeployer(address expectedOwner, address caller);

    /// @notice Peer chain ID cannot be zero.
    error InvalidPeerChainIdZero();

    /// @notice Peer cannot be the zero address.
    error InvalidPeerZeroAddress();

    error InvalidOperator(address operator, address expectedOperator);

    error InvalidRecipient();
    error ZeroTokenIds();
    error ExceedsMaxBatchSize(uint256 batchSize, uint256 maxBatchSize);

    /// @notice Peer for the chain does not match the configuration.
    /// @param chainId ChainId of the source chain.
    /// @param peerAddress Address of the peer nttManager contract.
    error InvalidPeer(uint16 chainId, bytes32 peerAddress);

    /// @notice The mode is invalid. It is neither in LOCKING or BURNING mode.
    /// @param mode The mode.
    error InvalidMode(uint8 mode);

    /// @notice Error when trying to execute a message on an unintended target chain.
    /// @dev Selector 0x3dcb204a.
    /// @param targetChain The target chain.
    /// @param thisChain The current chain.
    error InvalidTargetChain(uint16 targetChain, uint16 thisChain);

    error InvalidTokenIdWidth(uint8 tokenIdWidth);

    /// @notice Sets the corresponding peer.
    /// @dev The NonFungiblenttManager that executes the message sets the source NonFungibleNttManager
    /// as the peer.
    /// @param peerChainId The chain ID of the peer.
    /// @param peerContract The address of the peer nttManager contract.c
    function setPeer(uint16 peerChainId, bytes32 peerContract) external;

    function getPeer(uint16 chainId_) external view returns (NonFungibleNttManagerPeer memory);

    function getMaxBatchSize() external pure returns (uint8);

    function transfer(
        uint256[] memory tokenIds,
        uint16 recipientChain,
        bytes32 recipient,
        bytes memory transceiverInstructions
    ) external payable returns (uint64);

    function executeMsg(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.ManagerMessage memory message
    ) external;
}

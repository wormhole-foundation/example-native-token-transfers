// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

import "../src/interfaces/INonFungibleNttManager.sol";
import "../src/interfaces/IManagerBase.sol";
import "../src/interfaces/IWormholeTransceiverState.sol";

import "../src/NativeTransfers/NonFungibleNttManager.sol";
import "../src/NativeTransfers/shared/TransceiverRegistry.sol";
import "../src/Transceiver/WormholeTransceiver/WormholeTransceiverState.sol";
import "../src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import "./interfaces/ITransceiverReceiver.sol";

import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "wormhole-solidity-sdk/Utils.sol";

import "./libraries/TransceiverHelpers.sol";
import "./libraries/NttManagerHelpers.sol";
import {Utils} from "./libraries/Utils.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/libraries/external/OwnableUpgradeable.sol";

import "./mocks/MockTransceivers.sol";
import "../src/mocks/DummyNft.sol";

contract TestNonFungibleNttManager is Test {
    uint16 constant chainIdOne = 2;
    uint16 constant chainIdTwo = 6;
    uint16 constant chainIdThree = 10;
    bytes4 constant WH_TRANSCEIVER_PAYLOAD_PREFIX = 0x9945FF10;
    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;
    address relayer = 0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470;
    uint8 consistencyLevel = 1;
    uint256 baseGasLimit = 500000;

    address owner = makeAddr("owner");

    // Deployed contracts.
    DummyNftMintAndBurn nftOne;
    DummyNftMintAndBurn nftTwo;
    INonFungibleNttManager managerOne;
    INonFungibleNttManager managerTwo;
    INonFungibleNttManager managerThree;
    WormholeTransceiver transceiverOne;
    WormholeTransceiver transceiverTwo;
    WormholeTransceiver transceiverThree;

    function deployNonFungibleManager(
        address nft,
        IManagerBase.Mode _mode,
        uint16 _chainId,
        bool shouldInitialize
    ) internal returns (INonFungibleNttManager) {
        NonFungibleNttManager implementation =
            new NonFungibleNttManager(address(nft), _mode, _chainId);

        NonFungibleNttManager proxy =
            NonFungibleNttManager(address(new ERC1967Proxy(address(implementation), "")));

        if (shouldInitialize) {
            proxy.initialize();
        }

        return INonFungibleNttManager(address(proxy));
    }

    function deployWormholeTranceiver(address manager) internal returns (WormholeTransceiver) {
        // Wormhole Transceivers.
        WormholeTransceiver implementation = new WormholeTransceiver(
            manager,
            address(guardian.wormhole()),
            relayer,
            address(0),
            consistencyLevel,
            baseGasLimit,
            IWormholeTransceiverState.ManagerType.ERC721
        );

        WormholeTransceiver transceiverProxy =
            WormholeTransceiver(address(new ERC1967Proxy(address(implementation), "")));

        transceiverProxy.initialize();

        return transceiverProxy;
    }

    function setUp() public {
        string memory url = "https://ethereum-sepolia-rpc.publicnode.com";
        IWormhole wormhole = IWormhole(0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78);
        vm.createSelectFork(url);
        initialBlockTimestamp = vm.getBlockTimestamp();

        guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);

        // Deploy contracts as owner.
        vm.startPrank(owner);

        // Nft collection.
        nftOne = new DummyNftMintAndBurn(bytes("https://metadata.dn69.com/y/"));
        nftTwo = new DummyNftMintAndBurn(bytes("https://metadata.dn420.com/y/"));

        // Managers.
        managerOne =
            deployNonFungibleManager(address(nftOne), IManagerBase.Mode.LOCKING, chainIdOne, true);
        managerTwo =
            deployNonFungibleManager(address(nftTwo), IManagerBase.Mode.BURNING, chainIdTwo, true);
        managerThree =
            deployNonFungibleManager(address(nftOne), IManagerBase.Mode.BURNING, chainIdThree, true);

        // Wormhole Transceivers.
        transceiverOne = deployWormholeTranceiver(address(managerOne));
        transceiverTwo = deployWormholeTranceiver(address(managerTwo));
        transceiverThree = deployWormholeTranceiver(address(managerThree));

        transceiverOne.setWormholePeer(chainIdTwo, toWormholeFormat(address(transceiverTwo)));
        transceiverTwo.setWormholePeer(chainIdOne, toWormholeFormat(address(transceiverOne)));
        transceiverTwo.setWormholePeer(chainIdThree, toWormholeFormat(address(transceiverThree)));
        transceiverThree.setWormholePeer(chainIdTwo, toWormholeFormat(address(transceiverTwo)));

        // Register transceivers and peers.
        managerOne.setTransceiver(address(transceiverOne));
        managerTwo.setTransceiver(address(transceiverTwo));
        managerThree.setTransceiver(address(transceiverThree));

        managerOne.setPeer(chainIdTwo, toWormholeFormat(address(managerTwo)));
        managerTwo.setPeer(chainIdOne, toWormholeFormat(address(managerOne)));
        managerTwo.setPeer(chainIdThree, toWormholeFormat(address(managerThree)));
        managerThree.setPeer(chainIdTwo, toWormholeFormat(address(managerTwo)));

        vm.stopPrank();
    }

    // ================================== Admin Tests ==================================

    function test_cannotInitalizeNotDeployer() public {
        // Don't initialize.
        vm.prank(owner);
        INonFungibleNttManager dummyManager =
            deployNonFungibleManager(address(nftOne), IManagerBase.Mode.LOCKING, chainIdOne, false);

        vm.prank(makeAddr("notOwner"));
        vm.expectRevert(
            abi.encodeWithSelector(
                INonFungibleNttManager.UnexpectedDeployer.selector, owner, makeAddr("notOwner")
            )
        );
        NonFungibleNttManager(address(dummyManager)).initialize();
    }

    function test_setPeerAsOwner() public {
        uint16 chainId = 69;
        bytes32 newPeer = toWormholeFormat(makeAddr("newPeer"));

        vm.startPrank(owner);

        bytes32 oldPeer = managerOne.getPeer(chainId).peerAddress;
        assertEq(oldPeer, bytes32(0), "Old peer should be zero address");

        managerOne.setPeer(chainId, newPeer);

        bytes32 updatedPeer = managerOne.getPeer(chainId).peerAddress;
        assertEq(updatedPeer, newPeer, "Peer should be updated");

        vm.stopPrank();
    }

    function test_updatePeerAsOwner() public {
        uint16 chainId = 69;
        bytes32 newPeer = toWormholeFormat(makeAddr("newPeer"));
        bytes32 updatedPeer = toWormholeFormat(makeAddr("updatedPeer"));

        vm.startPrank(owner);

        // Set the peer to newPeer.
        {
            managerOne.setPeer(chainId, newPeer);
            bytes32 peer = managerOne.getPeer(chainId).peerAddress;
            assertEq(peer, newPeer, "Peer should be newPeer");
        }

        // Update to a new peer.
        {
            managerOne.setPeer(chainId, updatedPeer);
            bytes32 peer = managerOne.getPeer(chainId).peerAddress;
            assertEq(peer, updatedPeer, "Peer should be updatedPeer");
        }

        vm.stopPrank();
    }

    function test_cannotUpdatePeerOwnerOnly() public {
        uint16 chainId = 69;
        bytes32 newPeer = toWormholeFormat(makeAddr("newPeer"));

        vm.prank(makeAddr("notOwner"));
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector, makeAddr("notOwner")
            )
        );
        managerOne.setPeer(chainId, newPeer);
    }

    function test_cannotSetPeerWithZeroChainId() public {
        uint16 chainId = 0;
        bytes32 newPeer = toWormholeFormat(makeAddr("newPeer"));

        vm.prank(owner);
        vm.expectRevert(INonFungibleNttManager.InvalidPeerChainIdZero.selector);
        managerOne.setPeer(chainId, newPeer);
    }

    function test_cannotSetPeerWithZeroAddress() public {
        uint16 chainId = 69;
        bytes32 newPeer = bytes32(0);

        vm.prank(owner);
        vm.expectRevert(INonFungibleNttManager.InvalidPeerZeroAddress.selector);
        managerOne.setPeer(chainId, newPeer);
    }

    // ============================ Transfer Tests ======================================

    function test_lockAndMint(uint256 nftCount, uint256 startId) public {
        nftCount = bound(nftCount, 1, managerOne.getMaxBatchSize());
        startId = bound(startId, 0, type(uint256).max - nftCount);

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Lock the NFTs on managerOne.
        bytes memory encodedVm = _approveAndTransferBatch(
            managerOne, transceiverOne, nftOne, tokenIds, recipient, chainIdTwo, true
        )[0];

        _verifyTransferPayload(encodedVm, managerOne, recipient, chainIdTwo, tokenIds);

        // Receive the message and mint the NFTs on managerTwo.
        transceiverTwo.receiveMessage(encodedVm);

        // Verify state changes. The NFTs should still be locked on managerOne, and a new
        // batch of NFTs should be minted on managerTwo.
        assertTrue(managerTwo.isMessageExecuted(_computeMessageDigest(chainIdOne, encodedVm)));
        assertTrue(_isBatchOwner(nftTwo, tokenIds, recipient), "Recipient should own NFTs");
        assertTrue(_isBatchOwner(nftOne, tokenIds, address(managerOne)), "Manager should own NFTs");
    }

    function test_burnAndUnlock(uint256 nftCount, uint256 startId) public {
        nftCount = bound(nftCount, 1, managerTwo.getMaxBatchSize());
        startId = bound(startId, 0, type(uint256).max - nftCount);

        // Mint nftOne to managerOne to "lock" them.
        {
            vm.startPrank(address(managerOne));
            uint256[] memory tokenIds =
                _mintNftBatch(nftOne, address(managerOne), nftCount, startId);
            assertTrue(
                _isBatchOwner(nftOne, tokenIds, address(managerOne)), "Manager should own NFTs"
            );
            vm.stopPrank();
        }

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftTwo, recipient, nftCount, startId);

        // Burn the NFTs on managerTwo.
        bytes memory encodedVm = _approveAndTransferBatch(
            managerTwo, transceiverTwo, nftTwo, tokenIds, recipient, chainIdOne, true
        )[0];

        _verifyTransferPayload(encodedVm, managerTwo, recipient, chainIdOne, tokenIds);

        // Receive the message and unlock the NFTs on managerOne.
        transceiverOne.receiveMessage(encodedVm);

        // Verify state changes.
        assertTrue(managerOne.isMessageExecuted(_computeMessageDigest(chainIdTwo, encodedVm)));
        assertTrue(_isBatchBurned(nftTwo, tokenIds), "NFTs should be burned");
        assertTrue(_isBatchOwner(nftOne, tokenIds, recipient), "Recipient should own NFTs");
    }

    function test_burnAndMint(uint256 nftCount, uint256 startId) public {
        nftCount = bound(nftCount, 1, managerOne.getMaxBatchSize());
        startId = bound(startId, 0, type(uint256).max - nftCount);

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Burn the NFTs on managerThree.
        bytes memory encodedVm = _approveAndTransferBatch(
            managerThree, transceiverThree, nftOne, tokenIds, recipient, chainIdTwo, true
        )[0];

        _verifyTransferPayload(encodedVm, managerThree, recipient, chainIdTwo, tokenIds);

        // Receive the message and mint the NFTs on managerTwo.
        transceiverTwo.receiveMessage(encodedVm);

        // Verify state changes. The NFTs should've been burned on managerThree, and a new
        // batch of NFTs should be minted on managerTwo.
        assertTrue(managerTwo.isMessageExecuted(_computeMessageDigest(chainIdThree, encodedVm)));
        assertTrue(_isBatchBurned(nftOne, tokenIds), "NFTs should be burned");
        assertTrue(_isBatchOwner(nftTwo, tokenIds, recipient), "Recipient should own NFTs");
    }

    // ================================ Negative Transfer Tests ==================================

    function test_cannotTransferZeroTokens() public {
        uint256[] memory tokenIds = new uint256[](0);
        address recipient = makeAddr("recipient");

        vm.startPrank(recipient);
        vm.expectRevert(abi.encodeWithSelector(INonFungibleNttManager.ZeroTokenIds.selector));
        managerOne.transfer(
            tokenIds,
            chainIdTwo,
            toWormholeFormat(recipient),
            new bytes(1)
        );
    }

    function test_cannotTransferExceedsMaxBatchSize() public {
        uint256 nftCount = managerOne.getMaxBatchSize() + 1;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        vm.startPrank(recipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                INonFungibleNttManager.ExceedsMaxBatchSize.selector,
                nftCount,
                managerOne.getMaxBatchSize()
            )
        );
        managerOne.transfer(
            tokenIds,
            chainIdTwo,
            toWormholeFormat(recipient),
            new bytes(1)
        );
    }

    function test_cannotTransferToInvalidChain() public {
        uint256 nftCount = 1;
        uint256 startId = 0;
        uint16 targetChain = 69;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        vm.startPrank(recipient);
        nftOne.setApprovalForAll(address(managerOne), true);
        vm.expectRevert(
            abi.encodeWithSelector(
                INonFungibleNttManager.InvalidPeer.selector, targetChain, bytes32(0)
            )
        );
        managerOne.transfer(
            tokenIds,
            targetChain,
            toWormholeFormat(recipient),
            new bytes(1)
        );
    }

    function test_cannotTransferInvalidRecipient() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        vm.startPrank(recipient);
        nftOne.setApprovalForAll(address(managerOne), true);
        vm.expectRevert(INonFungibleNttManager.InvalidRecipient.selector);
        managerOne.transfer(
            tokenIds,
            chainIdTwo,
            bytes32(0), // Invalid Recipient.
            new bytes(1)
        );
    }

    function test_cannotTransferDuplicateNfts() public {
        uint256 nftCount = 2;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Create new tokenIds array.
        uint256[] memory tokenIds2 = new uint256[](nftCount + 1);
        for (uint256 i = 0; i < nftCount; i++) {
            tokenIds2[i] = tokenIds[i];
        }
        tokenIds2[nftCount] = tokenIds[0];

        vm.startPrank(recipient);
        nftOne.setApprovalForAll(address(managerOne), true);
        vm.expectRevert("ERC721: transfer from incorrect owner");
        managerOne.transfer(
            tokenIds2,
            chainIdTwo,
            toWormholeFormat(recipient),
            new bytes(1)
        );
    }

    // ==================================== Helpers =======================================

    function _isBatchOwner(
        DummyNftMintAndBurn nft,
        uint256[] memory tokenIds,
        address _owner
    ) internal view returns (bool) {
        bool isOwner = true;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (nft.ownerOf(tokenIds[i]) != _owner) {
                isOwner = false;
                break;
            }
        }
        return isOwner;
    }

    function _isBatchBurned(
        DummyNftMintAndBurn nft,
        uint256[] memory tokenIds
    ) internal view returns (bool) {
        bool isBurned = true;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (nft.exists(tokenIds[i])) {
                isBurned = false;
                break;
            }
        }
        return isBurned;
    }

    function _verifyTransferPayload(
        bytes memory transferMessage,
        INonFungibleNttManager manager,
        address recipient,
        uint16 targetChain,
        uint256[] memory tokenIds
    ) internal {
        // Verify the manager message
        bytes memory vmPayload = guardian.wormhole().parseVM(transferMessage).payload;
        (, TransceiverStructs.ManagerMessage memory message) = TransceiverStructs
            .parseTransceiverAndManagerMessage(WH_TRANSCEIVER_PAYLOAD_PREFIX, vmPayload);

        assertEq(uint256(message.id), manager.nextMessageSequence() - 1);
        assertEq(message.sender, toWormholeFormat(recipient));

        // Verify the non-fungible transfer message.
        TransceiverStructs.NonFungibleNativeTokenTransfer memory nftTransfer =
            TransceiverStructs.parseNonFungibleNativeTokenTransfer(message.payload);

        assertEq(nftTransfer.to, toWormholeFormat(recipient));
        assertEq(nftTransfer.toChain, targetChain);
        assertEq(nftTransfer.payload, new bytes(0));
        assertEq(nftTransfer.tokenIds.length, tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(nftTransfer.tokenIds[i], tokenIds[i]);
        }
    }

    function _computeMessageDigest(
        uint16 sourceChain,
        bytes memory encodedVm
    ) internal view returns (bytes32 digest) {
        // Parse the manager message.
        bytes memory vmPayload = guardian.wormhole().parseVM(encodedVm).payload;
        (, TransceiverStructs.ManagerMessage memory message) = TransceiverStructs
            .parseTransceiverAndManagerMessage(WH_TRANSCEIVER_PAYLOAD_PREFIX, vmPayload);

        digest = TransceiverStructs.managerMessageDigest(sourceChain, message);
    }

    function _approveAndTransferBatch(
        INonFungibleNttManager manager,
        WormholeTransceiver transceiver,
        DummyNftMintAndBurn nft,
        uint256[] memory tokenIds,
        address recipient,
        uint16 targetChain,
        bool relayerOff
    ) internal returns (bytes[] memory encodedVms) {
        // Transfer NFTs as the owner of the NFTs.
        vm.startPrank(recipient);
        nft.setApprovalForAll(address(manager), true);

        vm.recordLogs();
        manager.transfer(
            tokenIds,
            targetChain,
            toWormholeFormat(recipient),
            _encodeTransceiverInstruction(relayerOff, transceiver)
        );
        vm.stopPrank();

        // Fetch the wormhole message.
        encodedVms = _getWormholeMessage(vm.getRecordedLogs(), manager.chainId());
    }

    function _mintNftBatch(
        DummyNftMintAndBurn nft,
        address recipient,
        uint256 len,
        uint256 start
    ) internal returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            uint256 tokenId = start + i;
            arr[i] = tokenId;

            nft.mint(recipient, tokenId);
        }
        return arr;
    }

    function _getWormholeMessage(
        Vm.Log[] memory logs,
        uint16 emitterChain
    ) internal view returns (bytes[] memory) {
        Vm.Log[] memory entries = guardian.fetchWormholeMessageFromLog(logs);
        bytes[] memory encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = guardian.fetchSignedMessageFromLogs(entries[i], emitterChain);
        }

        return encodedVMs;
    }

    function _encodeTransceiverInstruction(
        bool relayerOff,
        WormholeTransceiver transceiver
    ) internal view returns (bytes memory) {
        WormholeTransceiver.WormholeTransceiverInstruction memory instruction =
            IWormholeTransceiver.WormholeTransceiverInstruction(relayerOff);
        bytes memory encodedInstructionWormhole =
            transceiver.encodeWormholeTransceiverInstruction(instruction);
        TransceiverStructs.TransceiverInstruction memory TransceiverInstruction = TransceiverStructs
            .TransceiverInstruction({index: 0, payload: encodedInstructionWormhole});
        TransceiverStructs.TransceiverInstruction[] memory TransceiverInstructions =
            new TransceiverStructs.TransceiverInstruction[](1);
        TransceiverInstructions[0] = TransceiverInstruction;
        return TransceiverStructs.encodeTransceiverInstructions(TransceiverInstructions);
    }
}

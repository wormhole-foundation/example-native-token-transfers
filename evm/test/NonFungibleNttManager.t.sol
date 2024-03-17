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
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "./mocks/MockTransceivers.sol";
import "../src/mocks/DummyNft.sol";

contract TestNonFungibleNttManager is Test {
    using BytesParsing for bytes;

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
    uint8 tokenIdWidth = 2;

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
            new NonFungibleNttManager(address(nft), tokenIdWidth, _mode, _chainId);

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

    /// @dev This function assumes that the two managers are already cross registered.
    function _setupMultiTransceiverManagers(
        INonFungibleNttManager sourceManager,
        INonFungibleNttManager targetManager
    ) internal returns (WormholeTransceiver) {
        vm.startPrank(owner);

        // Deploy two new transceivers.
        WormholeTransceiver sourceTransceiver = deployWormholeTranceiver(address(sourceManager));
        WormholeTransceiver targetTransceiver = deployWormholeTranceiver(address(targetManager));

        // Register transceivers and peers.
        sourceManager.setTransceiver(address(sourceTransceiver));
        targetManager.setTransceiver(address(targetTransceiver));

        sourceTransceiver.setWormholePeer(
            targetManager.chainId(), toWormholeFormat(address(targetTransceiver))
        );
        targetTransceiver.setWormholePeer(
            sourceManager.chainId(), toWormholeFormat(address(sourceTransceiver))
        );

        sourceManager.setThreshold(2);
        targetManager.setThreshold(2);

        vm.stopPrank();

        return targetTransceiver;
    }

    // ================================== Admin Tests ==================================

    function test_cannotDeployWithInvalidTokenIdWidth(uint8 _tokenIdWidth) public {
        vm.assume(
            _tokenIdWidth != 1 && _tokenIdWidth != 2 && _tokenIdWidth != 4 && _tokenIdWidth != 8
                && _tokenIdWidth != 16 && _tokenIdWidth != 32
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                INonFungibleNttManager.InvalidTokenIdWidth.selector, _tokenIdWidth
            )
        );
        NonFungibleNttManager implementation = new NonFungibleNttManager(
            address(nftOne), _tokenIdWidth, IManagerBase.Mode.BURNING, chainIdOne
        );
    }

    /// @dev We perform an upgrade with the existing tokenIdWidth to show that upgrades
    /// are possible with the same tokenIdWidth. There is no specific error thrown when
    /// the immutables check throws.
    function test_cannotUpgradeWithDifferentTokenIdWidth() public {
        vm.startPrank(owner);
        {
            NonFungibleNttManager newImplementation = new NonFungibleNttManager(
                address(nftOne), tokenIdWidth, IManagerBase.Mode.LOCKING, chainIdOne
            );
            managerOne.upgrade(address(newImplementation));
        }

        uint8 newTokenIdWidth = 4;
        NonFungibleNttManager newImplementation = new NonFungibleNttManager(
            address(nftOne), newTokenIdWidth, IManagerBase.Mode.LOCKING, chainIdOne
        );

        vm.expectRevert();
        managerOne.upgrade(address(newImplementation));
    }

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

    // ============================ Serde Tests ======================================

    function test_serde(
        uint8 tokenIdWidth,
        bytes32 to,
        uint16 toChain,
        bytes memory payload,
        uint256 nftCount,
        uint256 startId
    ) public {
        // Narrow the search.
        tokenIdWidth = uint8(bound(tokenIdWidth, 1, 32));
        // Ugly, but necessary.
        vm.assume(
            tokenIdWidth == 1 || tokenIdWidth == 2 || tokenIdWidth == 4 || tokenIdWidth == 8
                || tokenIdWidth == 16 || tokenIdWidth == 32
        );
        vm.assume(to != bytes32(0));
        vm.assume(toChain != 0);
        nftCount = bound(nftCount, 1, managerOne.getMaxBatchSize());
        startId = bound(startId, 0, _getMaxFromTokenIdWidth(tokenIdWidth) - nftCount);

        TransceiverStructs.NonFungibleNativeTokenTransfer memory nftTransfer = TransceiverStructs
            .NonFungibleNativeTokenTransfer({
            to: to,
            toChain: toChain,
            payload: payload,
            tokenIds: _createBatchTokenIds(nftCount, startId)
        });

        bytes memory encoded =
            TransceiverStructs.encodeNonFungibleNativeTokenTransfer(nftTransfer, tokenIdWidth);

        TransceiverStructs.NonFungibleNativeTokenTransfer memory out =
            TransceiverStructs.parseNonFungibleNativeTokenTransfer(encoded);

        assertEq(out.to, to, "To address should be the same");
        assertEq(out.toChain, toChain, "To chain should be the same");
        assertEq(out.payload, payload, "Payload should be the same");
        assertEq(
            out.tokenIds.length, nftTransfer.tokenIds.length, "TokenIds length should be the same"
        );

        for (uint256 i = 0; i < nftCount; i++) {
            assertEq(out.tokenIds[i], nftTransfer.tokenIds[i], "TokenId should be the same");
        }
    }

    /// @dev Skip testing 32byte tokenIdWidth as uint256(max) + 1 is too large to test.
    function test_cannotEncodeTokenIdTooLarge(uint8 tokenIdWidth) public {
        tokenIdWidth = uint8(bound(tokenIdWidth, 1, 16));
        vm.assume(
            tokenIdWidth == 1 || tokenIdWidth == 2 || tokenIdWidth == 4 || tokenIdWidth == 8
                || tokenIdWidth == 16
        );
        uint256 tokenId = _getMaxFromTokenIdWidth(tokenIdWidth) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                TransceiverStructs.TokenIdTooLarge.selector, tokenId, tokenId - 1
            )
        );
        TransceiverStructs.encodeTokenId(tokenId, tokenIdWidth);
    }

    // ============================ Transfer Tests ======================================

    function test_lockAndMint(uint16 nftCount, uint16 startId) public {
        nftCount = uint16(bound(nftCount, 1, managerOne.getMaxBatchSize()));
        startId = uint16(bound(startId, 0, type(uint16).max - nftCount));

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

    function test_lockAndMintMultiTransceiver(uint16 nftCount, uint16 startId) public {
        nftCount = uint16(bound(nftCount, 1, managerOne.getMaxBatchSize()));
        startId = uint16(bound(startId, 0, type(uint16).max - nftCount));

        WormholeTransceiver multiTransceiverTwo =
            _setupMultiTransceiverManagers(managerOne, managerTwo);

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Lock the NFTs on managerOne.
        bytes[] memory vms = _approveAndTransferBatch(
            managerOne, transceiverOne, nftOne, tokenIds, recipient, chainIdTwo, true
        );
        assertEq(vms.length, 2);

        _verifyTransferPayload(vms[0], managerOne, recipient, chainIdTwo, tokenIds);
        _verifyTransferPayload(vms[1], managerOne, recipient, chainIdTwo, tokenIds);

        // Receive the message and mint the NFTs on managerTwo.
        transceiverTwo.receiveMessage(vms[0]);
        assertFalse(managerTwo.isMessageExecuted(_computeMessageDigest(chainIdOne, vms[0])));
        multiTransceiverTwo.receiveMessage(vms[1]);

        // Verify state changes. The NFTs should still be locked on managerOne, and a new
        // batch of NFTs should be minted on managerTwo.
        assertTrue(managerTwo.isMessageExecuted(_computeMessageDigest(chainIdOne, vms[0])));
        assertTrue(_isBatchOwner(nftTwo, tokenIds, recipient), "Recipient should own NFTs");
        assertTrue(_isBatchOwner(nftOne, tokenIds, address(managerOne)), "Manager should own NFTs");
    }

    function test_burnAndUnlock(uint16 nftCount, uint16 startId) public {
        nftCount = uint16(bound(nftCount, 1, managerOne.getMaxBatchSize()));
        startId = uint16(bound(startId, 0, type(uint16).max - nftCount));

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

    function test_burnAndUnlockMultiTransceiver(uint16 nftCount, uint16 startId) public {
        nftCount = uint16(bound(nftCount, 1, managerOne.getMaxBatchSize()));
        startId = uint16(bound(startId, 0, type(uint16).max - nftCount));

        WormholeTransceiver multiTransceiverOne =
            _setupMultiTransceiverManagers(managerTwo, managerOne);

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
        bytes[] memory vms = _approveAndTransferBatch(
            managerTwo, transceiverTwo, nftTwo, tokenIds, recipient, chainIdOne, true
        );
        assertEq(vms.length, 2);

        _verifyTransferPayload(vms[0], managerTwo, recipient, chainIdOne, tokenIds);
        _verifyTransferPayload(vms[1], managerTwo, recipient, chainIdOne, tokenIds);

        // Receive the message and unlock the NFTs on managerOne.
        transceiverOne.receiveMessage(vms[0]);
        assertFalse(managerOne.isMessageExecuted(_computeMessageDigest(chainIdTwo, vms[0])));
        multiTransceiverOne.receiveMessage(vms[1]);

        // Verify state changes.
        assertTrue(managerOne.isMessageExecuted(_computeMessageDigest(chainIdTwo, vms[0])));
        assertTrue(_isBatchBurned(nftTwo, tokenIds), "NFTs should be burned");
        assertTrue(_isBatchOwner(nftOne, tokenIds, recipient), "Recipient should own NFTs");
    }

    function test_burnAndMint(uint16 nftCount, uint16 startId) public {
        nftCount = uint16(bound(nftCount, 1, managerOne.getMaxBatchSize()));
        startId = uint16(bound(startId, 0, type(uint16).max - nftCount));

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

    function test_burnAndMintMultiTransceiver(uint16 nftCount, uint16 startId) public {
        nftCount = uint16(bound(nftCount, 1, managerOne.getMaxBatchSize()));
        startId = uint16(bound(startId, 0, type(uint16).max - nftCount));

        WormholeTransceiver multiTransceiverTwo =
            _setupMultiTransceiverManagers(managerThree, managerTwo);

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Burn the NFTs on managerThree.
        bytes[] memory vms = _approveAndTransferBatch(
            managerThree, transceiverThree, nftOne, tokenIds, recipient, chainIdTwo, true
        );
        assertEq(vms.length, 2);

        _verifyTransferPayload(vms[0], managerThree, recipient, chainIdTwo, tokenIds);
        _verifyTransferPayload(vms[1], managerThree, recipient, chainIdTwo, tokenIds);

        // Receive the message and mint the NFTs on managerTwo.
        transceiverTwo.receiveMessage(vms[0]);
        assertFalse(managerTwo.isMessageExecuted(_computeMessageDigest(chainIdThree, vms[0])));
        multiTransceiverTwo.receiveMessage(vms[1]);

        // Verify state changes. The NFTs should've been burned on managerThree, and a new
        // batch of NFTs should be minted on managerTwo.
        assertTrue(managerTwo.isMessageExecuted(_computeMessageDigest(chainIdThree, vms[0])));
        assertTrue(_isBatchBurned(nftOne, tokenIds), "NFTs should be burned");
        assertTrue(_isBatchOwner(nftTwo, tokenIds, recipient), "Recipient should own NFTs");
    }

    // ================================ Negative Transfer Tests ==================================

    function test_cannotTransferZeroTokens() public {
        uint256[] memory tokenIds = new uint256[](0);
        address recipient = makeAddr("recipient");

        vm.startPrank(recipient);
        vm.expectRevert(abi.encodeWithSelector(INonFungibleNttManager.ZeroTokenIds.selector));
        managerOne.transfer(tokenIds, chainIdTwo, toWormholeFormat(recipient), new bytes(1));
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
        managerOne.transfer(tokenIds, chainIdTwo, toWormholeFormat(recipient), new bytes(1));
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
            abi.encodeWithSelector(IManagerBase.PeerNotRegistered.selector, targetChain)
        );
        managerOne.transfer(tokenIds, targetChain, toWormholeFormat(recipient), new bytes(1));
    }

    function test_cannotTransferTokenIdTooLarge() public {
        uint256 nftCount = 1;
        uint256 startId = type(uint256).max - nftCount;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        vm.startPrank(recipient);
        nftOne.setApprovalForAll(address(managerOne), true);
        vm.expectRevert(
            abi.encodeWithSelector(
                TransceiverStructs.TokenIdTooLarge.selector, tokenIds[0], type(uint16).max
            )
        );
        managerOne.transfer(tokenIds, chainIdTwo, toWormholeFormat(recipient), new bytes(1));
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
        managerOne.transfer(tokenIds2, chainIdTwo, toWormholeFormat(recipient), new bytes(1));
    }

    function test_cannotTransferWhenPaused() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        vm.prank(owner);
        managerOne.pause();

        vm.startPrank(recipient);
        vm.expectRevert(PausableUpgradeable.RequireContractIsNotPaused.selector);
        managerOne.transfer(tokenIds, chainIdTwo, toWormholeFormat(recipient), new bytes(1));
    }

    function test_cannotTransferReentrant() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Enable reentrancy on nft.
        vm.prank(owner);
        nftOne.setReentrant(true);

        vm.startPrank(recipient);
        nftOne.setApprovalForAll(address(managerOne), true);

        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        managerOne.transfer(tokenIds, chainIdTwo, toWormholeFormat(recipient), new bytes(1));
    }

    function test_cannotExecuteMessagePeerNotRegistered() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Register managerThree on managerOne, but not vice versa.
        vm.startPrank(owner);
        managerOne.setPeer(chainIdThree, toWormholeFormat(address(managerThree)));
        transceiverThree.setWormholePeer(chainIdOne, toWormholeFormat(address(transceiverOne)));
        vm.stopPrank();

        // Burn the NFTs on managerThree.
        bytes memory encodedVm = _approveAndTransferBatch(
            managerOne, transceiverOne, nftOne, tokenIds, recipient, chainIdThree, true
        )[0];

        // Receive the message and mint the NFTs on managerTwo.
        vm.expectRevert(
            abi.encodeWithSelector(
                INonFungibleNttManager.InvalidPeer.selector,
                chainIdOne,
                toWormholeFormat(address(managerOne))
            )
        );
        transceiverThree.receiveMessage(encodedVm);
    }

    function test_cannotExecuteMessageNotApproved() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        bytes memory encodedVm = _approveAndTransferBatch(
            managerOne, transceiverOne, nftOne, tokenIds, recipient, chainIdTwo, true
        )[0];

        // Parse the manager message.
        bytes memory vmPayload = guardian.wormhole().parseVM(encodedVm).payload;
        (, TransceiverStructs.ManagerMessage memory message) = TransceiverStructs
            .parseTransceiverAndManagerMessage(WH_TRANSCEIVER_PAYLOAD_PREFIX, vmPayload);

        // Receive the message and mint the NFTs on managerTwo.
        vm.expectRevert(
            abi.encodeWithSelector(
                IManagerBase.MessageNotApproved.selector,
                _computeMessageDigest(chainIdOne, encodedVm)
            )
        );
        managerTwo.executeMsg(chainIdOne, toWormholeFormat(address(managerOne)), message);
    }

    function test_cannotExecuteMessageNotApproveMultiTransceiver() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        WormholeTransceiver multiTransceiverTwo =
            _setupMultiTransceiverManagers(managerOne, managerTwo);

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Lock the NFTs on managerOne.
        bytes[] memory vms = _approveAndTransferBatch(
            managerOne, transceiverOne, nftOne, tokenIds, recipient, chainIdTwo, true
        );
        assertEq(vms.length, 2);

        _verifyTransferPayload(vms[0], managerOne, recipient, chainIdTwo, tokenIds);
        _verifyTransferPayload(vms[1], managerOne, recipient, chainIdTwo, tokenIds);

        // Receive the message and mint the NFTs on managerTwo.
        transceiverTwo.receiveMessage(vms[0]);

        // Parse the manager message.
        bytes memory vmPayload = guardian.wormhole().parseVM(vms[1]).payload;
        (, TransceiverStructs.ManagerMessage memory message) = TransceiverStructs
            .parseTransceiverAndManagerMessage(WH_TRANSCEIVER_PAYLOAD_PREFIX, vmPayload);

        // Receive the message and mint the NFTs on managerTwo.
        vm.expectRevert(
            abi.encodeWithSelector(
                IManagerBase.MessageNotApproved.selector, _computeMessageDigest(chainIdOne, vms[1])
            )
        );
        managerTwo.executeMsg(chainIdOne, toWormholeFormat(address(managerOne)), message);
    }

    function test_cannotAttestMessageOnlyTranceiver() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        bytes memory encodedVm = _approveAndTransferBatch(
            managerOne, transceiverOne, nftOne, tokenIds, recipient, chainIdTwo, true
        )[0];

        // Parse the manager message.
        bytes memory vmPayload = guardian.wormhole().parseVM(encodedVm).payload;
        (, TransceiverStructs.ManagerMessage memory message) = TransceiverStructs
            .parseTransceiverAndManagerMessage(WH_TRANSCEIVER_PAYLOAD_PREFIX, vmPayload);

        // Receive the message and mint the NFTs on managerTwo.
        vm.expectRevert(
            abi.encodeWithSelector(TransceiverRegistry.CallerNotTransceiver.selector, address(this))
        );
        managerTwo.attestationReceived(chainIdOne, toWormholeFormat(address(managerOne)), message);
    }

    function test_cannotExecuteMessageInvalidTargetChain() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Register a manager on managerOne with chainIdThree, but use managerTwo address.
        // Otherwise, the recipient manager address would be unexpected.
        vm.prank(owner);
        managerOne.setPeer(chainIdThree, toWormholeFormat(address(managerTwo)));

        // Send the batch to chainThree, but receive it on chainTwo.
        bytes memory encodedVm = _approveAndTransferBatch(
            managerOne, transceiverOne, nftOne, tokenIds, recipient, chainIdThree, true
        )[0];

        vm.expectRevert(
            abi.encodeWithSelector(
                INonFungibleNttManager.InvalidTargetChain.selector, chainIdThree, chainIdTwo
            )
        );
        transceiverTwo.receiveMessage(encodedVm);
    }

    function test_cannotExecuteMessageWhenPaused() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Lock the NFTs on managerOne.
        bytes memory encodedVm = _approveAndTransferBatch(
            managerOne, transceiverOne, nftOne, tokenIds, recipient, chainIdTwo, true
        )[0];

        // Pause managerTwo.
        vm.prank(owner);
        managerTwo.pause();

        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.RequireContractIsNotPaused.selector)
        );
        transceiverTwo.receiveMessage(encodedVm);
    }

    function test_cannotAttestWhenPaused() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        WormholeTransceiver multiTransceiverTwo =
            _setupMultiTransceiverManagers(managerOne, managerTwo);

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        // Lock the NFTs on managerOne.
        bytes[] memory vms = _approveAndTransferBatch(
            managerOne, transceiverOne, nftOne, tokenIds, recipient, chainIdTwo, true
        );
        assertEq(vms.length, 2);

        _verifyTransferPayload(vms[0], managerOne, recipient, chainIdTwo, tokenIds);
        _verifyTransferPayload(vms[1], managerOne, recipient, chainIdTwo, tokenIds);

        // Receive the message and mint the NFTs on managerTwo.
        transceiverTwo.receiveMessage(vms[0]);

        // Pause managerTwo.
        vm.prank(owner);
        managerTwo.pause();

        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.RequireContractIsNotPaused.selector)
        );
        multiTransceiverTwo.receiveMessage(vms[1]);
    }

    function test_cannotReceiveErc721FromNonOperator() public {
        uint256 nftCount = 1;
        uint256 startId = 0;

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = _mintNftBatch(nftOne, recipient, nftCount, startId);

        vm.startPrank(recipient);
        nftOne.approve(address(managerOne), tokenIds[0]);

        vm.expectRevert(
            abi.encodeWithSelector(
                INonFungibleNttManager.InvalidOperator.selector, recipient, address(managerOne)
            )
        );
        nftOne.safeTransferFrom(recipient, address(managerOne), tokenIds[0]);
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

    function _createBatchTokenIds(
        uint256 len,
        uint256 start
    ) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            arr[i] = start + i;
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

    function _getMaxFromTokenIdWidth(uint8 tokenIdWidth) internal pure returns (uint256) {
        if (tokenIdWidth == 1) {
            return type(uint8).max;
        } else if (tokenIdWidth == 2) {
            return type(uint16).max;
        } else if (tokenIdWidth == 4) {
            return type(uint32).max;
        } else if (tokenIdWidth == 8) {
            return type(uint64).max;
        } else if (tokenIdWidth == 16) {
            return type(uint128).max;
        } else if (tokenIdWidth == 32) {
            return type(uint256).max;
        }
    }
}

// TODO:
// 1) Relayer test
// 2) Add max payload size and associated tests

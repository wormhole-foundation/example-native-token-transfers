// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

import "../src/interfaces/INonFungibleNttManager.sol";
import "../src/interfaces/IManagerBase.sol";

import "../src/NativeTransfers/NonFungibleNttManager.sol";
import "../src/NativeTransfers/shared/TransceiverRegistry.sol";
import "../src/Transceiver/WormholeTransceiver/WormholeTransceiverState.sol";
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
    bytes4 constant WH_TRANSCEIVER_PAYLOAD_PREFIX = 0x9945FF10;
    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;
    address relayer = 0x28D8F1Be96f97C1387e94A53e00eCcFb4E75175a;
    uint8 consistencyLevel = 1;
    uint256 baseGasLimit = 500000;

    address owner = makeAddr("owner");

    // Deployed contracts.
    DummyNftMintAndBurn nft;
    INonFungibleNttManager managerOne;
    INonFungibleNttManager managerTwo;
    MockWormholeTransceiverContract transceiverOne;
    MockWormholeTransceiverContract transceiverTwo;

    function deployNonFungibleManager(
        address _nft,
        IManagerBase.Mode _mode,
        uint16 _chainId,
        bool shouldInitialize
    ) internal returns (INonFungibleNttManager) {
        NonFungibleNttManager implementation =
            new NonFungibleNttManager(address(_nft), _mode, _chainId);

        NonFungibleNttManager proxy =
            NonFungibleNttManager(address(new ERC1967Proxy(address(implementation), "")));

        if (shouldInitialize) {
            proxy.initialize();
        }

        return INonFungibleNttManager(address(proxy));
    }

    function setUp() public {
        string memory url = "https://ethereum-goerli.publicnode.com";
        IWormhole wormhole = IWormhole(0x706abc4E45D419950511e474C7B9Ed348A4a716c);
        vm.createSelectFork(url);
        initialBlockTimestamp = vm.getBlockTimestamp();

        guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);

        // Deploy contracts as owner.
        vm.startPrank(owner);

        // Nft collection.
        nft = new DummyNftMintAndBurn(bytes("https://metadata.dn.com/y/"));

        // Managers.
        managerOne =
            deployNonFungibleManager(address(nft), IManagerBase.Mode.LOCKING, chainIdOne, true);
        managerTwo =
            deployNonFungibleManager(address(nft), IManagerBase.Mode.BURNING, chainIdTwo, true);

        // Wormhole Transceivers.
        transceiverOne = new MockWormholeTransceiverContract(
            address(managerOne),
            address(guardian.wormhole()),
            relayer,
            address(0),
            consistencyLevel,
            baseGasLimit
        );
        transceiverTwo = new MockWormholeTransceiverContract(
            address(managerTwo),
            address(guardian.wormhole()),
            relayer,
            address(0),
            consistencyLevel,
            baseGasLimit
        );

        // Register transceivers and peers.
        managerOne.setTransceiver(address(transceiverOne));
        managerTwo.setTransceiver(address(transceiverTwo));

        managerOne.setPeer(chainIdTwo, toWormholeFormat(address(managerTwo)));
        managerTwo.setPeer(chainIdOne, toWormholeFormat(address(managerOne)));

        vm.stopPrank();
    }

    // ================================== Admin Tests ==================================

    function test_cannotInitalizeNotDeployer() public {
        // Don't initialize.
        vm.prank(owner);
        INonFungibleNttManager dummyManager =
            deployNonFungibleManager(address(nft), IManagerBase.Mode.LOCKING, chainIdOne, false);

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

    // ============================ Business Logic Tests ==================================

    function test_transferLocked(uint256 nftCount) public {
        nftCount = bound(nftCount, 1, managerOne.getMaxBatchSize());

        address recipient = makeAddr("recipient");
        uint256[] memory tokenIds = mintNftBatch(nft, recipient, nftCount, 50);

        // Transfer NFTs as the owner of the NFTs.
        vm.startPrank(recipient);
        nft.setApprovalForAll(address(managerOne), true);

        vm.recordLogs();
        managerOne.transfer(
            tokenIds,
            chainIdTwo,
            toWormholeFormat(recipient),
            encodeTransceiverInstruction(true, transceiverOne)
        );
        vm.stopPrank();

        // Check if the NFTs are locked.
        for (uint256 i = 0; i < nftCount; i++) {
            uint256 tokenId = tokenIds[i];
            assertEq(nft.ownerOf(tokenId), address(managerOne), "NFT should be locked");
        }

        // Fetch the wormhole message.
        bytes memory encodedVm = getWormholeMessage(vm.getRecordedLogs(), chainIdOne)[0];

        // Verify the manager message
        bytes memory vmPayload = guardian.wormhole().parseVM(encodedVm).payload;
        (, TransceiverStructs.ManagerMessage memory message) = TransceiverStructs
            .parseTransceiverAndManagerMessage(WH_TRANSCEIVER_PAYLOAD_PREFIX, vmPayload);

        assertEq(uint256(message.id), managerOne.nextMessageSequence() - 1);
        assertEq(message.sender, toWormholeFormat(recipient));

        // Verify the non-fungible transfer message.
        TransceiverStructs.NonFungibleNativeTokenTransfer memory nftTransfer = TransceiverStructs
            .parseNonFungibleNativeTokenTransfer(message.payload);

        assertEq(nftTransfer.to, toWormholeFormat(recipient));
        assertEq(nftTransfer.toChain, chainIdTwo);
        assertEq(nftTransfer.payload, new bytes(0));
        assertEq(nftTransfer.tokenIds.length, nftCount);

        for (uint256 i = 0; i < nftCount; i++) {
            assertEq(nftTransfer.tokenIds[i], tokenIds[i]);
        }
    }

    // ==================================== Helpers =======================================

    function mintNftBatch(
        DummyNftMintAndBurn _nft,
        address recipient,
        uint256 len,
        uint256 start
    ) public returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            uint256 tokenId = start + i;
            arr[i] = tokenId;

            _nft.mint(recipient, tokenId);
        }
        return arr;
    }

    function getWormholeMessage(
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

    function encodeTransceiverInstruction(
        bool relayer_off,
        MockWormholeTransceiverContract transceiver
    ) public view returns (bytes memory) {
        WormholeTransceiver.WormholeTransceiverInstruction memory instruction =
            IWormholeTransceiver.WormholeTransceiverInstruction(relayer_off);
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

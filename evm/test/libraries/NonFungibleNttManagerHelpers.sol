// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "../../src/interfaces/INonFungibleNttManager.sol";
import "../../src/interfaces/IManagerBase.sol";
import "../../src/interfaces/IWormholeTransceiverState.sol";

import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import "../../src/NativeTransfers/NonFungibleNttManager.sol";

import "../mocks/MockTransceivers.sol";
import "../../src/mocks/DummyNft.sol";

contract NonFungibleNttHelpers is Test {
    bytes4 constant WH_TRANSCEIVER_PAYLOAD_PREFIX = 0x9945FF10;

    function deployNonFungibleManager(
        address nft,
        IManagerBase.Mode _mode,
        uint16 _chainId,
        bool shouldInitialize,
        uint8 _tokenIdWidth
    ) public returns (INonFungibleNttManager) {
        NonFungibleNttManager implementation =
            new NonFungibleNttManager(address(nft), _tokenIdWidth, _mode, _chainId);

        NonFungibleNttManager proxy =
            NonFungibleNttManager(address(new ERC1967Proxy(address(implementation), "")));

        if (shouldInitialize) {
            proxy.initialize();
        }

        return INonFungibleNttManager(address(proxy));
    }

    function deployWormholeTransceiver(
        WormholeSimulator guardian,
        address manager,
        address relayer,
        uint8 consistencyLevel,
        uint256 baseGasLimit
    ) public returns (WormholeTransceiver) {
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
        WormholeSimulator guardian,
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
        WormholeSimulator guardian,
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
        WormholeSimulator guardian,
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
        encodedVms = _getWormholeMessage(guardian, vm.getRecordedLogs(), manager.chainId());
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
        WormholeSimulator guardian,
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
    ) internal pure returns (bytes memory) {
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

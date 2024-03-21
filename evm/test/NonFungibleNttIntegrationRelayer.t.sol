// SPDX-License-Identifier: Apache 2
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

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
import "./libraries/NonFungibleNttManagerHelpers.sol";
import {Utils} from "./libraries/Utils.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/libraries/external/OwnableUpgradeable.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "./mocks/MockTransceivers.sol";
import "../src/mocks/DummyNft.sol";

import {WormholeRelayerBasicTest} from "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";

contract TestNonFungibleNttManagerWithRelayer is NonFungibleNttHelpers, WormholeRelayerBasicTest {
    uint16 constant SOURCE_CHAIN_ID = 6;
    uint16 constant TARGET_CHAIN_ID = 5;
    uint8 constant FAST_CONSISTENCY_LEVEL = 200;
    uint256 constant GAS_LIMIT = 500000;
    uint8 constant TOKEN_ID_WIDTH = 2;

    DummyNftMintAndBurn sourceNft;
    DummyNftMintAndBurn targetNft;
    INonFungibleNttManager sourceManager;
    INonFungibleNttManager targetManager;
    WormholeTransceiver sourceTransceiver;
    WormholeTransceiver targetTransceiver;

    address sender = makeAddr("sender");
    address recipient = makeAddr("recipient");

    constructor() {
        setTestnetForkChains(SOURCE_CHAIN_ID, TARGET_CHAIN_ID);
    }

    function setUpSource() public override {
        guardianSource = new WormholeSimulator(address(wormholeSource), DEVNET_GUARDIAN_PK);
        sourceNft = new DummyNftMintAndBurn(bytes("https://metadata.dn69.com/y/"));
        sourceManager = deployNonFungibleManager(
            address(sourceNft), IManagerBase.Mode.LOCKING, SOURCE_CHAIN_ID, true, TOKEN_ID_WIDTH
        );
        sourceTransceiver = deployWormholeTransceiver(
            guardianSource,
            address(sourceManager),
            address(relayerSource),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );

        sourceManager.setTransceiver(address(sourceTransceiver));
        sourceManager.setThreshold(1);

        vm.deal(sender, 10 ether);
    }

    function setUpTarget() public override {
        guardianTarget = new WormholeSimulator(address(wormholeTarget), DEVNET_GUARDIAN_PK);
        targetNft = new DummyNftMintAndBurn(bytes("https://metadata.dn420.com/y/"));
        targetManager = deployNonFungibleManager(
            address(targetNft), IManagerBase.Mode.BURNING, TARGET_CHAIN_ID, true, TOKEN_ID_WIDTH
        );
        targetTransceiver = deployWormholeTransceiver(
            guardianTarget,
            address(targetManager),
            address(relayerTarget),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );

        targetManager.setTransceiver(address(targetTransceiver));
        targetManager.setThreshold(1);

        vm.deal(recipient, 10 ether);
    }

    /// TODO: Fuzz test this in the same way as `test_lockAndMint` in `NonFungibleNttManager.t.sol`.
    function testRoundTripEvm() public {
        // Cross-register the contracts.
        {
            vm.selectFork(sourceFork);
            sourceTransceiver.setWormholePeer(
                TARGET_CHAIN_ID, toWormholeFormat(address(targetTransceiver))
            );
            sourceTransceiver.setIsWormholeRelayingEnabled(TARGET_CHAIN_ID, true);
            sourceTransceiver.setIsWormholeEvmChain(TARGET_CHAIN_ID, true);
            sourceManager.setPeer(TARGET_CHAIN_ID, toWormholeFormat(address(targetManager)));

            vm.selectFork(targetFork);
            targetTransceiver.setWormholePeer(
                SOURCE_CHAIN_ID, toWormholeFormat(address(sourceTransceiver))
            );
            targetTransceiver.setIsWormholeRelayingEnabled(SOURCE_CHAIN_ID, true);
            targetTransceiver.setIsWormholeEvmChain(SOURCE_CHAIN_ID, true);
            targetManager.setPeer(SOURCE_CHAIN_ID, toWormholeFormat(address(sourceManager)));
        }

        vm.selectFork(sourceFork);
        vm.recordLogs();

        // Mint a token on the source chain.
        uint16 nftCount = 1;
        uint256[] memory tokenIds = _mintNftBatch(sourceNft, sender, nftCount, 0);

        // Fetch quote and execute the transfer.
        {
            bytes memory transceiverInstructions =
                _encodeTransceiverInstruction(false, sourceTransceiver);
            (, uint256 quote) =
                sourceManager.quoteDeliveryPrice(TARGET_CHAIN_ID, transceiverInstructions);
            console.log("Quote: ", quote);
        }
    }
}

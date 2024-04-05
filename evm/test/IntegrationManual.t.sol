// SPDX-License-Identifier: Apache 2
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {WormholeRelayerBasicTest} from "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";
import "./libraries/IntegrationHelpers.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "../src/NttManager/NttManager.sol";
import "./mocks/MockNttManager.sol";
import "./mocks/MockTransceivers.sol";

import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestRelayerEndToEndManual is IntegrationHelpers, IRateLimiterEvents {
    NttManager nttManagerChain1;
    NttManager nttManagerChain2;

    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    uint16 constant chainId1 = 4;
    uint16 constant chainId2 = 5;
    uint8 constant FAST_CONSISTENCY_LEVEL = 200;
    uint256 constant GAS_LIMIT = 500000;

    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;

    address userA = address(0x123);
    address userB = address(0x456);
    address userC = address(0x789);
    address userD = address(0xABC);

    address relayer = address(0x80aC94316391752A193C1c47E27D382b507c93F3);
    IWormhole wormhole = IWormhole(0x68605AD7b15c732a30b1BbC62BE8F2A509D74b4D);

    function setUp() public {
        string memory url = "https://bsc-testnet-rpc.publicnode.com";
        vm.createSelectFork(url);
        initialBlockTimestamp = vm.getBlockTimestamp();

        guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);

        vm.chainId(chainId1);
        DummyToken t1 = new DummyToken();
        NttManager implementation = new MockNttManagerContract(
            address(t1), IManagerBase.Mode.LOCKING, chainId1, 1 days, false
        );

        nttManagerChain1 =
            MockNttManagerContract(address(new ERC1967Proxy(address(implementation), "")));
        nttManagerChain1.initialize();

        wormholeTransceiverChain1 = new MockWormholeTransceiverContract(
            address(nttManagerChain1),
            address(wormhole),
            address(relayer),
            address(0x0),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );
        wormholeTransceiverChain1 = MockWormholeTransceiverContract(
            address(new ERC1967Proxy(address(wormholeTransceiverChain1), ""))
        );
        wormholeTransceiverChain1.initialize();

        nttManagerChain1.setTransceiver(address(wormholeTransceiverChain1));
        nttManagerChain1.setOutboundLimit(type(uint64).max);
        nttManagerChain1.setInboundLimit(type(uint64).max, chainId2);

        // Chain 2 setup
        vm.chainId(chainId2);
        DummyToken t2 = new DummyTokenMintAndBurn();
        NttManager implementationChain2 = new MockNttManagerContract(
            address(t2), IManagerBase.Mode.BURNING, chainId2, 1 days, false
        );

        nttManagerChain2 =
            MockNttManagerContract(address(new ERC1967Proxy(address(implementationChain2), "")));
        nttManagerChain2.initialize();
        wormholeTransceiverChain2 = new MockWormholeTransceiverContract(
            address(nttManagerChain2),
            address(wormhole),
            address(relayer), // TODO - add support for this later
            address(0x0), // TODO - add support for this later
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );
        wormholeTransceiverChain2 = MockWormholeTransceiverContract(
            address(new ERC1967Proxy(address(wormholeTransceiverChain2), ""))
        );
        wormholeTransceiverChain2.initialize();

        nttManagerChain2.setTransceiver(address(wormholeTransceiverChain2));
        nttManagerChain2.setOutboundLimit(type(uint64).max);
        nttManagerChain2.setInboundLimit(type(uint64).max, chainId1);

        // Register peer contracts for the nttManager and transceiver. Transceivers and nttManager each have the concept of peers here.
        nttManagerChain1.setPeer(
            chainId2, bytes32(uint256(uint160(address(nttManagerChain2)))), 9, type(uint64).max
        );
        nttManagerChain2.setPeer(
            chainId1, bytes32(uint256(uint160(address(nttManagerChain1)))), 7, type(uint64).max
        );
    }

    function test_relayerTransceiverAuth() public {
        // Set up sensible WH transceiver peers
        _setTransceiverPeers(
            [wormholeTransceiverChain1, wormholeTransceiverChain2],
            [wormholeTransceiverChain2, wormholeTransceiverChain1],
            [chainId2, chainId1]
        );

        vm.recordLogs();
        vm.chainId(chainId1);

        // Setting up the transfer
        DummyToken token1 = DummyToken(nttManagerChain1.token());

        uint8 decimals = token1.decimals();
        uint256 sendingAmount = 5 * 10 ** decimals;
        _prepareTransfer(token1, userA, address(nttManagerChain1), sendingAmount);

        vm.deal(userA, 1 ether);
        WormholeTransceiver[] memory transceiver = new WormholeTransceiver[](1);
        transceiver[0] = wormholeTransceiverChain1;

        // Send token through the relayer
        transferToken(userB, userA, nttManagerChain1, sendingAmount, chainId2, transceiver, false);

        // Get the messages from the logs for the sender
        vm.chainId(chainId2);

        bytes[] memory encodedVMs = _getWormholeMessage(guardian, vm.getRecordedLogs(), chainId1);

        IWormhole.VM memory vaa = wormhole.parseVM(encodedVMs[0]);

        vm.stopPrank();
        vm.chainId(chainId2);

        // Set bad manager peer (0x1)
        nttManagerChain2.setPeer(chainId1, toWormholeFormat(address(0x1)), 9, type(uint64).max);

        vm.startPrank(relayer);

        bytes[] memory a;
        vm.expectRevert(
            abi.encodeWithSelector(
                INttManager.InvalidPeer.selector, chainId1, address(nttManagerChain1)
            )
        );
        _receiveWormholeMessage(
            vaa, wormholeTransceiverChain1, wormholeTransceiverChain2, vaa.emitterChainId, a
        );
        vm.stopPrank();

        _setManagerPeer(nttManagerChain2, nttManagerChain1, chainId1, 9, type(uint64).max);

        // Wrong caller - aka not relayer contract
        vm.prank(userD);
        vm.expectRevert(
            abi.encodeWithSelector(IWormholeTransceiverState.CallerNotRelayer.selector, userD)
        );
        _receiveWormholeMessage(
            vaa, wormholeTransceiverChain1, wormholeTransceiverChain2, vaa.emitterChainId, a
        );

        vm.startPrank(relayer);

        // Bad chain ID for a given transceiver
        vm.expectRevert(
            abi.encodeWithSelector(
                IWormholeTransceiver.InvalidWormholePeer.selector,
                0xFF,
                address(wormholeTransceiverChain1)
            )
        );
        wormholeTransceiverChain2.receiveWormholeMessages(
            vaa.payload,
            a,
            bytes32(uint256(uint160(address(wormholeTransceiverChain1)))),
            0xFF,
            vaa.hash
        );

        /*
        This information is assumed to be trusted since ONLY the relayer on a given chain can call it.
        However, it's still good to test various things.

        This attempt should actually work this time.
        */
        wormholeTransceiverChain2.receiveWormholeMessages(
            vaa.payload, // Verified
            a, // Should be zero
            bytes32(uint256(uint160(address(wormholeTransceiverChain1)))), // Must be a wormhole peers
            vaa.emitterChainId, // ChainID from the call
            vaa.hash // Hash of the VAA being used
        );

        // Should from sending a *duplicate* message
        vm.expectRevert(
            abi.encodeWithSelector(IWormholeTransceiver.TransferAlreadyCompleted.selector, vaa.hash)
        );
        wormholeTransceiverChain2.receiveWormholeMessages(
            vaa.payload,
            a, // Should be zero
            bytes32(uint256(uint160(address(wormholeTransceiverChain1)))), // Must be a wormhole peers
            vaa.emitterChainId, // ChainID from the call
            vaa.hash // Hash of the VAA being used
        );
    }

    function test_relayerWithInvalidWHTransceiver() public {
        // Set up dodgy wormhole transceiver peers
        wormholeTransceiverChain2.setWormholePeer(chainId1, bytes32(uint256(uint160(address(0x1)))));
        wormholeTransceiverChain1.setWormholePeer(
            chainId2, bytes32(uint256(uint160(address(wormholeTransceiverChain2))))
        );

        vm.recordLogs();
        vm.chainId(chainId1);

        // Setting up the transfer
        DummyToken token1 = DummyToken(nttManagerChain1.token());

        uint8 decimals = token1.decimals();
        uint256 sendingAmount = 5 * 10 ** decimals;
        token1.mintDummy(address(userA), 5 * 10 ** decimals);
        vm.startPrank(userA);
        token1.approve(address(nttManagerChain1), sendingAmount);

        // Send token through the relayer
        {
            vm.deal(userA, 1 ether);
            nttManagerChain1.transfer{
                value: wormholeTransceiverChain1.quoteDeliveryPrice(
                    chainId2, buildTransceiverInstruction(false)
                )
            }(
                sendingAmount,
                chainId2,
                bytes32(uint256(uint160(userB))),
                bytes32(uint256(uint160(userA))),
                false,
                encodeTransceiverInstruction(false)
            );
        }

        // Get the messages from the logs for the sender
        vm.chainId(chainId2);
        Vm.Log[] memory entries = guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        bytes[] memory encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = guardian.fetchSignedMessageFromLogs(entries[i], chainId1);
        }

        IWormhole.VM memory vaa = wormhole.parseVM(encodedVMs[0]);

        vm.stopPrank();
        vm.chainId(chainId2);

        // Caller is not proper who to receive messages from
        bytes[] memory a;
        vm.startPrank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWormholeTransceiver.InvalidWormholePeer.selector,
                chainId1,
                address(wormholeTransceiverChain1)
            )
        );
        wormholeTransceiverChain2.receiveWormholeMessages(
            vaa.payload,
            a,
            bytes32(uint256(uint160(address(wormholeTransceiverChain1)))),
            vaa.emitterChainId,
            vaa.hash
        );
        vm.stopPrank();
    }
}

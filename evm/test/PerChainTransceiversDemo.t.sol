// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/NttManager/NttManagerNoRateLimiting.sol";
import "../src/Transceiver/Transceiver.sol";
import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IRateLimiter.sol";
import "../src/interfaces/ITransceiver.sol";
import "../src/interfaces/IManagerBase.sol";
import "../src/interfaces/IRateLimiterEvents.sol";
import {Utils} from "./libraries/Utils.sol";
import {DummyToken, DummyTokenMintAndBurn} from "./NttManager.t.sol";
import "../src/interfaces/IWormholeTransceiver.sol";
import {WormholeTransceiver} from "../src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import "../src/libraries/TransceiverStructs.sol";
import "./mocks/MockNttManager.sol";
import "./mocks/MockTransceivers.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "wormhole-solidity-sdk/Utils.sol";
//import "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";

// This contract demonstrates how per-chain transceivers could be used based on the following configuration.
//
// Chain1 ↔ Chain2
//
// 1. Chain1 → Chain2
//     a. Send (on Chain1): via both transceivers
//     b. Receive (on Chain2): Require 2-of-2, both transceivers
// 2. Chain2 → Chain1
//     a. Send (on Chain2): via first transceiver only
//     b. Receive (on Chain1): require first transceiver only (1-of-?)
//
// For this test, we will use the mock wormhole transceiver for both, but will configure separate ones
// with the appropriate thresholds. We will then do a transfer.

contract TestPerChainTransceiversDemo is Test, IRateLimiterEvents {
    MockNttManagerNoRateLimitingContractForTest nttManagerChain1;
    MockNttManagerNoRateLimitingContractForTest nttManagerChain2;

    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    uint16 constant chainId1 = 101;
    uint16 constant chainId2 = 102;
    uint8 constant FAST_CONSISTENCY_LEVEL = 200;
    uint256 constant GAS_LIMIT = 500000;

    uint16 constant SENDING_CHAIN_ID = 2;
    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;

    WormholeTransceiver chainOneFirstTransceiver;
    WormholeTransceiver chainOneSecondTransceiver;
    WormholeTransceiver chainTwoFirstTransceiver;
    WormholeTransceiver chainTwoSecondTransceiver;

    address userA = address(0x123);
    address userB = address(0x456);
    address userC = address(0x789);
    address userD = address(0xABC);

    address relayer = address(0x28D8F1Be96f97C1387e94A53e00eCcFb4E75175a);
    IWormhole wormhole = IWormhole(0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78);

    function setUp() public {
        string memory url = "https://ethereum-sepolia-rpc.publicnode.com";
        vm.createSelectFork(url);
        initialBlockTimestamp = vm.getBlockTimestamp();

        guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);

        // Set up the manager on chain one. //////////////////////////////////////////////////////////////////
        vm.chainId(chainId1);
        DummyToken t1 = new DummyToken();
        NttManager implementation = new MockNttManagerNoRateLimitingContractForTest(
            address(t1), IManagerBase.Mode.LOCKING, chainId1
        );

        nttManagerChain1 = MockNttManagerNoRateLimitingContractForTest(
            address(new ERC1967Proxy(address(implementation), ""))
        );
        nttManagerChain1.initialize();

        // Create the first transceiver on chain one.
        WormholeTransceiver chainOneFirstTransceiverImplementation = new MockWormholeTransceiverContract(
            address(nttManagerChain1),
            address(wormhole),
            address(relayer),
            address(0x0),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );
        chainOneFirstTransceiver = MockWormholeTransceiverContract(
            address(new ERC1967Proxy(address(chainOneFirstTransceiverImplementation), ""))
        );

        chainOneFirstTransceiver.initialize();
        nttManagerChain1.setTransceiver(address(chainOneFirstTransceiver));

        // Create the second transceiver for chain one.
        WormholeTransceiver chainOneSecondTransceiverImplementation = new MockWormholeTransceiverContract(
            address(nttManagerChain1),
            address(wormhole),
            address(relayer),
            address(0x0),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );
        chainOneSecondTransceiver = MockWormholeTransceiverContract(
            address(new ERC1967Proxy(address(chainOneSecondTransceiverImplementation), ""))
        );

        chainOneSecondTransceiver.initialize();
        nttManagerChain1.setTransceiver(address(chainOneSecondTransceiver));

        // Set up the manager on chain two. //////////////////////////////////////////////////////////////////
        vm.chainId(chainId2);
        DummyToken t2 = new DummyTokenMintAndBurn();
        NttManager implementationChain2 = new MockNttManagerNoRateLimitingContractForTest(
            address(t2), IManagerBase.Mode.BURNING, chainId2
        );

        nttManagerChain2 = MockNttManagerNoRateLimitingContractForTest(
            address(new ERC1967Proxy(address(implementationChain2), ""))
        );
        nttManagerChain2.initialize();

        // Create the first transceiver on chain two.
        WormholeTransceiver chainTwoFirstTransceiverImplementation = new MockWormholeTransceiverContract(
            address(nttManagerChain2),
            address(wormhole),
            address(relayer),
            address(0x0),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );
        chainTwoFirstTransceiver = MockWormholeTransceiverContract(
            address(new ERC1967Proxy(address(chainTwoFirstTransceiverImplementation), ""))
        );
        chainTwoFirstTransceiver.initialize();

        nttManagerChain2.setTransceiver(address(chainTwoFirstTransceiver));

        // Create the second transceiver on chain two.
        WormholeTransceiver chainTwoSecondTransceiverImplementation = new MockWormholeTransceiverContract(
            address(nttManagerChain2),
            address(wormhole),
            address(relayer),
            address(0x0),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );
        chainTwoSecondTransceiver = MockWormholeTransceiverContract(
            address(new ERC1967Proxy(address(chainTwoSecondTransceiverImplementation), ""))
        );

        chainTwoSecondTransceiver.initialize();
        nttManagerChain2.setTransceiver(address(chainTwoSecondTransceiver));

        // Register the two NTT manager peers. //////////////////////////////////////////////////////////////////
        nttManagerChain1.setPeer(
            chainId2, bytes32(uint256(uint160(address(nttManagerChain2)))), 9, type(uint64).max
        );
        nttManagerChain2.setPeer(
            chainId1, bytes32(uint256(uint160(address(nttManagerChain1)))), 7, type(uint64).max
        );

        // Register the transceiver peers. //////////////////////////////////////////////////////////////////
        chainOneFirstTransceiver.setWormholePeer(
            chainId2, bytes32(uint256(uint160(address(chainTwoFirstTransceiver))))
        );
        chainTwoFirstTransceiver.setWormholePeer(
            chainId1, bytes32(uint256(uint160(address(chainOneFirstTransceiver))))
        );
        chainOneSecondTransceiver.setWormholePeer(
            chainId2, bytes32(uint256(uint160(address(chainTwoSecondTransceiver))))
        );
        chainTwoSecondTransceiver.setWormholePeer(
            chainId1, bytes32(uint256(uint160(address(chainOneSecondTransceiver))))
        );

        // Set the default thresholds. //////////////////////////////////////////////////////////////////////
        nttManagerChain1.setThreshold(2);
        nttManagerChain2.setThreshold(2);

        // Set up our per-chain transceivers and thresholds. ////////////////////////////////////////////////

        // Set up chain one.
        // 1.a:
        nttManagerChain1.enableSendTransceiverForChain(address(chainOneFirstTransceiver), chainId2);
        nttManagerChain1.enableSendTransceiverForChain(address(chainOneSecondTransceiver), chainId2);
        // 2.b:
        nttManagerChain1.enableRecvTransceiverForChain(address(chainOneFirstTransceiver), chainId2);
        nttManagerChain1.setPerChainThreshold(chainId2, 1);

        // Set up chain two.
        // 2.a:
        nttManagerChain2.enableSendTransceiverForChain(address(chainTwoFirstTransceiver), chainId1);
        // 1.b:
        nttManagerChain2.enableRecvTransceiverForChain(address(chainTwoFirstTransceiver), chainId1);
        nttManagerChain2.enableRecvTransceiverForChain(address(chainTwoSecondTransceiver), chainId1);
        nttManagerChain2.setPerChainThreshold(chainId1, 2);
    }

    function test_verifyConfig() public view {
        // Verify config of chain one. //////////////////////////////////////////////////////////
        require(
            nttManagerChain1.isSendTransceiverEnabledForChain(
                address(chainOneFirstTransceiver), chainId2
            ),
            "On chain 1, first transceiver should be enabled for sending to chain 2"
        );
        require(
            nttManagerChain1.isSendTransceiverEnabledForChain(
                address(chainOneFirstTransceiver), chainId2
            ),
            "On chain 1, second transceiver should be enabled for sending to chain 2"
        );
        require(
            nttManagerChain1.getEnabledRecvTransceiversForChain(chainId2) == 0x1,
            "On chain 1, only first transceiver should be enabled for receiving from chain 2"
        );
        require(nttManagerChain1.getThreshold() == 2, "On chain 1, the default threshold is wrong");
        require(
            nttManagerChain1.getPerChainThreshold(chainId2) == 1,
            "On chain 1, threshold for chain 2 is wrong"
        );

        // Verify config of chain two. //////////////////////////////////////////////////////////
        require(
            nttManagerChain2.isSendTransceiverEnabledForChain(
                address(chainTwoFirstTransceiver), chainId1
            ),
            "On chain 2, first transceiver should be enabled for sending to chain 1"
        );
        require(
            !nttManagerChain2.isSendTransceiverEnabledForChain(
                address(chainTwoSecondTransceiver), chainId1
            ),
            "On chain 2, second transceiver should be not enabled for sending to chain 1"
        );
        require(
            nttManagerChain2.getEnabledRecvTransceiversForChain(chainId1) == 0x3,
            "On chain 2, both transceivers should be enabled for receiving from chain 1"
        );
        require(nttManagerChain2.getThreshold() == 2, "On chain 2, the default threshold is wrong");
        require(
            nttManagerChain2.getPerChainThreshold(chainId1) == 2,
            "On chain 2, threshold for chain 1 is wrong"
        );
    }

    function test_transfer() public {
        vm.chainId(chainId1);

        // Setting up the transfer
        DummyToken token1 = DummyToken(nttManagerChain1.token());
        DummyToken token2 = DummyTokenMintAndBurn(nttManagerChain2.token());

        uint8 decimals = token1.decimals();
        uint256 sendingAmount = 5 * 10 ** decimals;
        token1.mintDummy(address(userA), 5 * 10 ** decimals);

        // Transfer tokens from chain one to chain two through standard means (not relayer)
        vm.startPrank(userA);
        token1.approve(address(nttManagerChain1), sendingAmount);
        vm.recordLogs();
        {
            uint256 nttManagerBalanceBefore = token1.balanceOf(address(nttManagerChain1));
            uint256 userBalanceBefore = token1.balanceOf(address(userA));
            nttManagerChain1.transfer(sendingAmount, chainId2, bytes32(uint256(uint160(userB))));

            // Balance check on funds going in and out working as expected
            uint256 nttManagerBalanceAfter = token1.balanceOf(address(nttManagerChain1));
            uint256 userBalanceAfter = token1.balanceOf(address(userB));
            require(
                nttManagerBalanceBefore + sendingAmount == nttManagerBalanceAfter,
                "Should be locking the tokens"
            );
            require(
                userBalanceBefore - sendingAmount == userBalanceAfter,
                "User should have sent tokens"
            );
        }

        vm.stopPrank();

        // Get the logs. There should be two messages going from chain 1 to chain 2.
        Vm.Log[] memory entries = guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        require(2 == entries.length, "Unexpected number of log entries 1");
        bytes[] memory encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = guardian.fetchSignedMessageFromLogs(entries[i], chainId1);
        }

        // Chain2 verification and checks
        vm.chainId(chainId2);

        {
            uint256 supplyBefore = token2.totalSupply();

            // Receiving the first VAA on the first transceiver shouldn't do anything.
            chainTwoFirstTransceiver.receiveMessage(encodedVMs[0]);
            uint256 supplyAfter = token2.totalSupply();
            require(supplyBefore == supplyAfter, "It looks like the transfer happened too soon");

            // Receiving the first VAA on the second transceiver should revert.
            vm.expectRevert(
                abi.encodeWithSelector(
                    IWormholeTransceiver.InvalidWormholePeer.selector,
                    chainId1,
                    chainOneFirstTransceiver
                )
            );
            chainTwoSecondTransceiver.receiveMessage(encodedVMs[0]);

            // Receiving the second VAA on the second one should complete the transfer.
            chainTwoSecondTransceiver.receiveMessage(encodedVMs[1]);
            supplyAfter = token2.totalSupply();

            require(sendingAmount + supplyBefore == supplyAfter, "Supplies dont match");
            require(token2.balanceOf(userB) == sendingAmount, "User didn't receive tokens");
            require(
                token2.balanceOf(address(nttManagerChain2)) == 0, "NttManager has unintended funds"
            );
        }

        // Go back the other way from a THIRD user
        vm.prank(userB);
        token2.transfer(userC, sendingAmount);

        vm.startPrank(userC);
        token2.approve(address(nttManagerChain2), sendingAmount);
        vm.recordLogs();

        // Supply checks on the transfer
        {
            uint256 supplyBefore = token2.totalSupply();
            nttManagerChain2.transfer(
                sendingAmount,
                chainId1,
                toWormholeFormat(userD),
                toWormholeFormat(userC),
                false,
                encodeTransceiverInstruction(true)
            );

            uint256 supplyAfter = token2.totalSupply();

            require(sendingAmount - supplyBefore == supplyAfter, "Supplies don't match");
            require(token2.balanceOf(userB) == 0, "OG user receive tokens");
            require(token2.balanceOf(userC) == 0, "Sending user didn't receive tokens");
            require(
                token2.balanceOf(address(nttManagerChain2)) == 0,
                "NttManager didn't receive unintended funds"
            );
        }

        // Get the logs. There should only be one message going from chain 2 to chain 1.
        entries = guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        require(1 == entries.length, "Unexpected number of log entries 2");
        encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = guardian.fetchSignedMessageFromLogs(entries[i], chainId2);
        }

        // Chain1 verification and checks with the receiving of the message
        vm.chainId(chainId1);

        {
            // Receiving a single VAA should do the trick.
            uint256 supplyBefore = token1.totalSupply();
            chainOneFirstTransceiver.receiveMessage(encodedVMs[0]);
            uint256 supplyAfter = token1.totalSupply();

            require(supplyBefore == supplyAfter, "Supplies don't match between operations");
            require(token1.balanceOf(userB) == 0, "OG user receive tokens");
            require(token1.balanceOf(userC) == 0, "Sending user didn't receive tokens");
            require(token1.balanceOf(userD) == sendingAmount, "User received funds");
        }
    }

    function encodeTransceiverInstruction(
        bool relayer_off
    ) public view returns (bytes memory) {
        WormholeTransceiver.WormholeTransceiverInstruction memory instruction =
            IWormholeTransceiver.WormholeTransceiverInstruction(relayer_off);
        bytes memory encodedInstructionWormhole =
            chainOneFirstTransceiver.encodeWormholeTransceiverInstruction(instruction);
        TransceiverStructs.TransceiverInstruction memory TransceiverInstruction = TransceiverStructs
            .TransceiverInstruction({index: 0, payload: encodedInstructionWormhole});
        TransceiverStructs.TransceiverInstruction[] memory TransceiverInstructions =
            new TransceiverStructs.TransceiverInstruction[](1);
        TransceiverInstructions[0] = TransceiverInstruction;
        return TransceiverStructs.encodeTransceiverInstructions(TransceiverInstructions);
    }

    // Encode an instruction for each of the relayers
    function encodeTransceiverInstructions(
        bool relayer_off
    ) public view returns (bytes memory) {
        WormholeTransceiver.WormholeTransceiverInstruction memory instruction =
            IWormholeTransceiver.WormholeTransceiverInstruction(relayer_off);

        bytes memory encodedInstructionWormhole =
            chainOneFirstTransceiver.encodeWormholeTransceiverInstruction(instruction);

        TransceiverStructs.TransceiverInstruction memory TransceiverInstruction1 =
        TransceiverStructs.TransceiverInstruction({index: 0, payload: encodedInstructionWormhole});
        TransceiverStructs.TransceiverInstruction memory TransceiverInstruction2 =
        TransceiverStructs.TransceiverInstruction({index: 1, payload: encodedInstructionWormhole});

        TransceiverStructs.TransceiverInstruction[] memory TransceiverInstructions =
            new TransceiverStructs.TransceiverInstruction[](2);

        TransceiverInstructions[0] = TransceiverInstruction1;
        TransceiverInstructions[1] = TransceiverInstruction2;

        return TransceiverStructs.encodeTransceiverInstructions(TransceiverInstructions);
    }
}

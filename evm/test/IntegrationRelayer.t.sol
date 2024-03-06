// SPDX-License-Identifier: Apache 2
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/NttManager/NttManager.sol";
import "../src/Transceiver/Transceiver.sol";
import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IRateLimiter.sol";
import "../src/interfaces/INttManagerEvents.sol";
import "../src/interfaces/IRateLimiterEvents.sol";
import "../src/interfaces/IWormholeTransceiver.sol";
import "../src/interfaces/IWormholeTransceiverState.sol";
import {Utils} from "./libraries/Utils.sol";
import {DummyToken, DummyTokenMintAndBurn} from "../src/mocks/DummyToken.sol";
import {WormholeTransceiver} from "../src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import "../src/libraries/TransceiverStructs.sol";
import "./mocks/MockNttManager.sol";
import "./mocks/MockTransceivers.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "wormhole-solidity-sdk/Utils.sol";
import {WormholeRelayerBasicTest} from "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";

contract TestEndToEndRelayerBase is Test {
    WormholeTransceiver wormholeTransceiverChain1;
    WormholeTransceiver wormholeTransceiverChain2;

    function buildTransceiverInstruction(bool relayer_off)
        public
        view
        returns (TransceiverStructs.TransceiverInstruction memory)
    {
        WormholeTransceiver.WormholeTransceiverInstruction memory instruction =
            IWormholeTransceiver.WormholeTransceiverInstruction(relayer_off);

        bytes memory encodedInstructionWormhole;
        // Source fork has id 0 and corresponds to chain 1
        if (vm.activeFork() == 0) {
            encodedInstructionWormhole =
                wormholeTransceiverChain1.encodeWormholeTransceiverInstruction(instruction);
        } else {
            encodedInstructionWormhole =
                wormholeTransceiverChain2.encodeWormholeTransceiverInstruction(instruction);
        }
        return TransceiverStructs.TransceiverInstruction({
            index: 0,
            payload: encodedInstructionWormhole
        });
    }

    function encodeTransceiverInstruction(bool relayer_off) public view returns (bytes memory) {
        TransceiverStructs.TransceiverInstruction memory TransceiverInstruction =
            buildTransceiverInstruction(relayer_off);
        TransceiverStructs.TransceiverInstruction[] memory TransceiverInstructions =
            new TransceiverStructs.TransceiverInstruction[](1);
        TransceiverInstructions[0] = TransceiverInstruction;
        return TransceiverStructs.encodeTransceiverInstructions(TransceiverInstructions);
    }
}

contract TestEndToEndRelayer is
    TestEndToEndRelayerBase,
    INttManagerEvents,
    IRateLimiterEvents,
    WormholeRelayerBasicTest
{
    NttManager nttManagerChain1;
    NttManager nttManagerChain2;

    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    uint16 constant chainId1 = 4;
    uint16 constant chainId2 = 5;
    uint8 constant FAST_CONSISTENCY_LEVEL = 200;
    uint256 constant GAS_LIMIT = 500000;

    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;

    address userA = address(0x123);
    address userB = address(0x456);
    address userC = address(0x789);
    address userD = address(0xABC);

    constructor() {
        setTestnetForkChains(chainId1, chainId2);
    }

    // https://github.com/wormhole-foundation/hello-wormhole/blob/main/test/HelloWormhole.t.sol#L14C1-L20C6
    // Setup the starting point of the network
    function setUpSource() public override {
        vm.deal(userA, 1 ether);
        DummyToken t1 = new DummyToken();

        NttManager implementation = new MockNttManagerContract(
            address(t1), INttManager.Mode.LOCKING, chainId1, 1 days, false
        );

        nttManagerChain1 =
            MockNttManagerContract(address(new ERC1967Proxy(address(implementation), "")));
        nttManagerChain1.initialize();

        wormholeTransceiverChain1 = new MockWormholeTransceiverContract(
            address(nttManagerChain1),
            address(chainInfosTestnet[chainId1].wormhole),
            address(relayerSource),
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
        nttManagerChain1.setThreshold(1);
    }

    // Setup the chain to relay to of the network
    function setUpTarget() public override {
        vm.deal(userC, 1 ether);

        // Chain 2 setup
        DummyToken t2 = new DummyTokenMintAndBurn();
        NttManager implementationChain2 = new MockNttManagerContract(
            address(t2), INttManager.Mode.BURNING, chainId2, 1 days, false
        );

        nttManagerChain2 =
            MockNttManagerContract(address(new ERC1967Proxy(address(implementationChain2), "")));
        nttManagerChain2.initialize();
        wormholeTransceiverChain2 = new MockWormholeTransceiverContract(
            address(nttManagerChain2),
            address(chainInfosTestnet[chainId2].wormhole),
            address(relayerTarget),
            address(0x0),
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

        nttManagerChain2.setThreshold(1);
    }

    function test_chainToChainReverts() public {
        // record all of the logs for all of the occuring events
        vm.recordLogs();

        // Setup the information for interacting with the chains
        vm.selectFork(targetFork);
        wormholeTransceiverChain2.setWormholePeer(
            chainId1, bytes32(uint256(uint160(address(wormholeTransceiverChain1))))
        );
        nttManagerChain2.setPeer(
            chainId1, bytes32(uint256(uint160(address(nttManagerChain1)))), 9, type(uint64).max
        );
        DummyToken token2 = DummyTokenMintAndBurn(nttManagerChain2.token());
        wormholeTransceiverChain2.setIsWormholeRelayingEnabled(chainId1, true);
        wormholeTransceiverChain2.setIsWormholeEvmChain(chainId1, true);

        // Register peer contracts for the nttManager and transceiver. Transceivers and nttManager each have the concept of peers here.
        vm.selectFork(sourceFork);
        DummyToken token1 = DummyToken(nttManagerChain1.token());
        wormholeTransceiverChain1.setWormholePeer(
            chainId2, bytes32(uint256(uint160((address(wormholeTransceiverChain2)))))
        );
        nttManagerChain1.setPeer(
            chainId2, bytes32(uint256(uint160(address(nttManagerChain2)))), 7, type(uint64).max
        );

        // Enable general relaying on the chain to transfer for the funds.
        wormholeTransceiverChain1.setIsWormholeRelayingEnabled(chainId2, true);
        wormholeTransceiverChain1.setIsWormholeEvmChain(chainId2, true);

        // Setting up the transfer
        uint8 decimals = token1.decimals();
        uint256 sendingAmount = 5 * 10 ** decimals;
        token1.mintDummy(address(userA), sendingAmount);
        vm.startPrank(userA);
        token1.approve(address(nttManagerChain1), sendingAmount);

        // Send token through standard means (not relayer)
        {
            uint256 nttManagerBalanceBefore = token1.balanceOf(address(nttManagerChain1));
            uint256 userBalanceBefore = token1.balanceOf(address(userA));

            uint256 priceQuote1 = wormholeTransceiverChain1.quoteDeliveryPrice(
                chainId2, buildTransceiverInstruction(false)
            );
            bytes memory instructions = encodeTransceiverInstruction(false);

            // set invalid config
            vm.stopPrank();
            wormholeTransceiverChain1.setIsWormholeEvmChain(chainId2, false);

            // config not set correctly
            vm.startPrank(userA);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IWormholeTransceiver.InvalidRelayingConfig.selector, chainId2
                )
            );
            nttManagerChain1.transfer{value: priceQuote1}(
                sendingAmount, chainId2, bytes32(uint256(uint160(userB))), false, instructions
            );

            // set valid config
            vm.stopPrank();
            wormholeTransceiverChain1.setIsWormholeEvmChain(chainId2, true);
            vm.startPrank(userA);

            // revert if transfer amount has dust
            uint256 amount = sendingAmount - 1;
            TrimmedAmount trimmedAmount = amount.trim(decimals, 7);
            uint256 newAmount = trimmedAmount.untrim(decimals);
            vm.expectRevert(
                abi.encodeWithSelector(
                    INttManager.TransferAmountHasDust.selector, amount, amount - newAmount
                )
            );
            nttManagerChain1.transfer{value: priceQuote1}(
                sendingAmount - 1, chainId2, bytes32(uint256(uint160(userB))), false, instructions
            );

            // Zero funds error
            vm.expectRevert(abi.encodeWithSelector(INttManager.ZeroAmount.selector));
            nttManagerChain1.transfer{value: priceQuote1}(
                0, chainId2, bytes32(uint256(uint160(userB))), false, instructions
            );

            // Not enough in gas costs from the 'quote'.
            vm.expectRevert(
                abi.encodeWithSelector(
                    INttManager.DeliveryPaymentTooLow.selector, priceQuote1, priceQuote1 - 1
                )
            );
            nttManagerChain1.transfer{value: priceQuote1 - 1}(
                sendingAmount, chainId2, bytes32(uint256(uint160(userB))), false, instructions
            );

            // Do the payment with slightly more gas than needed. This should result in a *payback* of 1 wei.
            nttManagerChain1.transfer{value: priceQuote1 + 1}(
                sendingAmount, chainId2, bytes32(uint256(uint160(userB))), false, instructions
            );

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

        vm.selectFork(targetFork); // Move to the target chain briefly to get the total supply
        uint256 supplyBefore = token2.totalSupply();

        // Deliver the TX via the relayer mechanism. That's pretty fly!
        vm.selectFork(sourceFork); // Move to back to the source chain for things to be processed

        // Turn on the log recording because we want the test framework to pick up the events.
        // TODO - can't do easy testing on this.
        // Foundry *eats* the logs. So, once this fails, they're gone forever. Need to set up signer then, prank then make the call to relay manually.
        performDelivery();

        vm.selectFork(targetFork); // Move to back to the target chain to look at how things were processed

        uint256 supplyAfter = token2.totalSupply();

        require(sendingAmount + supplyBefore == supplyAfter, "Supplies dont match");
        require(token2.balanceOf(userB) == sendingAmount, "User didn't receive tokens");
        require(token2.balanceOf(address(nttManagerChain2)) == 0, "NttManager has unintended funds");
    }

    function test_chainToChainBase() public {
        // record all of the logs for all of the occuring events
        vm.recordLogs();

        // Setup the information for interacting with the chains
        vm.selectFork(targetFork);
        wormholeTransceiverChain2.setWormholePeer(
            chainId1, bytes32(uint256(uint160(address(wormholeTransceiverChain1))))
        );
        nttManagerChain2.setPeer(
            chainId1, bytes32(uint256(uint160(address(nttManagerChain1)))), 9, type(uint64).max
        );
        DummyToken token2 = DummyTokenMintAndBurn(nttManagerChain2.token());
        wormholeTransceiverChain2.setIsWormholeRelayingEnabled(chainId1, true);
        wormholeTransceiverChain2.setIsWormholeEvmChain(chainId1, true);

        // Register peer contracts for the nttManager and transceiver. Transceivers and nttManager each have the concept of peers here.
        vm.selectFork(sourceFork);
        nttManagerChain1.setPeer(
            chainId2, bytes32(uint256(uint160(address(nttManagerChain2)))), 7, type(uint64).max
        );
        wormholeTransceiverChain1.setWormholePeer(
            chainId2, bytes32(uint256(uint160((address(wormholeTransceiverChain2)))))
        );
        DummyToken token1 = DummyToken(nttManagerChain1.token());

        // Enable general relaying on the chain to transfer for the funds.
        wormholeTransceiverChain1.setIsWormholeRelayingEnabled(chainId2, true);
        wormholeTransceiverChain1.setIsWormholeEvmChain(chainId2, true);

        // Setting up the transfer
        uint8 decimals = token1.decimals();
        uint256 sendingAmount = 5 * 10 ** decimals;
        token1.mintDummy(address(userA), 5 * 10 ** decimals);
        vm.startPrank(userA);
        token1.approve(address(nttManagerChain1), sendingAmount);

        // Send token through standard means (not relayer)
        {
            uint256 nttManagerBalanceBefore = token1.balanceOf(address(nttManagerChain1));
            uint256 userBalanceBefore = token1.balanceOf(address(userA));

            nttManagerChain1.transfer{
                value: wormholeTransceiverChain1.quoteDeliveryPrice(
                    chainId2, buildTransceiverInstruction(false)
                    )
            }(
                sendingAmount,
                chainId2,
                bytes32(uint256(uint160(userB))),
                false,
                encodeTransceiverInstruction(false)
            );

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

        vm.selectFork(targetFork); // Move to the target chain briefly to get the total supply
        uint256 supplyBefore = token2.totalSupply();

        // Deliver the TX via the relayer mechanism. That's pretty fly!
        vm.selectFork(sourceFork); // Move to back to the source chain for things to be processed
        // Turn on the log recording because we want the test framework to pick up the events.
        performDelivery();

        vm.selectFork(targetFork); // Move to back to the target chain to look at how things were processed

        uint256 supplyAfter = token2.totalSupply();

        require(sendingAmount + supplyBefore == supplyAfter, "Supplies not changed - minting");
        require(token2.balanceOf(userB) == sendingAmount, "User didn't receive tokens");
        require(token2.balanceOf(address(nttManagerChain2)) == 0, "NttManager has unintended funds");

        // Go back the other way from a THIRD user
        vm.prank(userB);
        token2.transfer(userC, sendingAmount);

        vm.startPrank(userC);
        token2.approve(address(nttManagerChain2), sendingAmount);

        {
            supplyBefore = token2.totalSupply();
            nttManagerChain2.transfer{
                value: wormholeTransceiverChain2.quoteDeliveryPrice(
                    chainId1, buildTransceiverInstruction(false)
                    )
            }(
                sendingAmount,
                chainId1,
                bytes32(uint256(uint160(userD))),
                false,
                encodeTransceiverInstruction(false)
            );

            supplyAfter = token2.totalSupply();

            require(
                sendingAmount - supplyBefore == supplyAfter,
                "Supplies don't match - tokens not burned"
            );
            require(token2.balanceOf(userB) == 0, "OG user receive tokens");
            require(token2.balanceOf(userC) == 0, "Sending user didn't receive tokens");
            require(
                token2.balanceOf(address(nttManagerChain2)) == 0,
                "NttManager didn't receive unintended funds"
            );
        }

        // Receive the transfer
        vm.selectFork(sourceFork); // Move to the source chain briefly to get the total supply
        supplyBefore = token1.totalSupply();

        vm.selectFork(targetFork); // Move to the target chain for log processing

        // Deliver the TX via the relayer mechanism. That's pretty fly!
        performDelivery();

        vm.selectFork(sourceFork); // Move back to the source chain to check out the balances

        require(supplyBefore - sendingAmount == supplyAfter, "Supplies weren't burned as expected");
        require(token1.balanceOf(userA) == 0, "UserA received funds on the transfer back");
        require(token1.balanceOf(userB) == 0, "UserB received funds on the transfer back");
        require(token1.balanceOf(userC) == 0, "UserC received funds on the transfer back");
        require(token1.balanceOf(userD) == sendingAmount, "User didn't receive tokens going back");
        require(
            token1.balanceOf(address(nttManagerChain1)) == 0,
            "NttManager has unintended funds going back"
        );
    }

    function copyBytes(bytes memory _bytes) private pure returns (bytes memory) {
        bytes memory copy = new bytes(_bytes.length);
        uint256 max = _bytes.length + 31;
        for (uint256 i = 32; i <= max; i += 32) {
            assembly {
                mstore(add(copy, i), mload(add(_bytes, i)))
            }
        }
        return copy;
    }
}

contract TestRelayerEndToEndManual is
    TestEndToEndRelayerBase,
    INttManagerEvents,
    IRateLimiterEvents
{
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
        string memory url = "https://bsc-testnet.public.blastapi.io";
        vm.createSelectFork(url);
        initialBlockTimestamp = vm.getBlockTimestamp();

        guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);

        vm.chainId(chainId1);
        DummyToken t1 = new DummyToken();
        NttManager implementation = new MockNttManagerContract(
            address(t1), INttManager.Mode.LOCKING, chainId1, 1 days, false
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
            address(t2), INttManager.Mode.BURNING, chainId2, 1 days, false
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
        wormholeTransceiverChain1.setWormholePeer(
            chainId2, bytes32(uint256(uint160((address(wormholeTransceiverChain2)))))
        );
        wormholeTransceiverChain2.setWormholePeer(
            chainId1, bytes32(uint256(uint160(address(wormholeTransceiverChain1))))
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

        bytes[] memory a;

        nttManagerChain2.setPeer(
            chainId1, bytes32(uint256(uint160(address(0x1)))), 9, type(uint64).max
        );
        vm.startPrank(relayer);

        // bad nttManager peer
        vm.expectRevert(
            abi.encodeWithSelector(
                INttManagerState.InvalidPeer.selector, chainId1, address(nttManagerChain1)
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

        // Wrong caller - aka not relayer contract
        nttManagerChain2.setPeer(
            chainId1, bytes32(uint256(uint160(address(nttManagerChain1)))), 9, type(uint64).max
        );
        vm.prank(userD);
        vm.expectRevert(
            abi.encodeWithSelector(IWormholeTransceiverState.CallerNotRelayer.selector, userD)
        );
        wormholeTransceiverChain2.receiveWormholeMessages(
            vaa.payload,
            a,
            bytes32(uint256(uint160(address(wormholeTransceiverChain1)))),
            vaa.emitterChainId,
            vaa.hash
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
            vaa.payload, // Verified
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

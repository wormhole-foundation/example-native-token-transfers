// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/ManagerStandalone.sol";
import "../src/EndpointAndManager.sol";
import "../src/EndpointStandalone.sol";
import "../src/interfaces/IManager.sol";
import "../src/interfaces/IRateLimiter.sol";
import "../src/interfaces/IManagerEvents.sol";
import "../src/interfaces/IRateLimiterEvents.sol";
import {Utils} from "./libraries/Utils.sol";
import {DummyToken, DummyTokenMintAndBurn} from "./Manager.t.sol";
import {WormholeEndpointStandalone} from "../src/WormholeEndpointStandalone.sol";
import "../src/interfaces/IWormholeEndpoint.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "wormhole-solidity-sdk/Utils.sol";
//import "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";


contract TestEndToEndBase is Test, IManagerEvents, IRateLimiterEvents {
    ManagerStandalone managerChain1;
    ManagerStandalone managerChain2;

    using NormalizedAmountLib for uint256;
    using NormalizedAmountLib for NormalizedAmount;

    uint16 constant chainId1 = 7;
    uint16 constant chainId2 = 100;

    uint16 constant SENDING_CHAIN_ID = 1;
    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;

    WormholeEndpointStandalone wormholeEndpointChain1; 
    WormholeEndpointStandalone wormholeEndpointChain2; 
    address userA = address(0x123); 
    address userB = address(0x456); 
    address userC = address(0x789);
    address userD = address(0xABC);

    address relayer = address(0x28D8F1Be96f97C1387e94A53e00eCcFb4E75175a);
    IWormhole wormhole = IWormhole(0x706abc4E45D419950511e474C7B9Ed348A4a716c);


    function setUp() public {
        string memory url = "https://ethereum-goerli.publicnode.com";
        vm.createSelectFork(url);
        initialBlockTimestamp = vm.getBlockTimestamp();

        guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);

        vm.chainId(chainId1);
        DummyToken t1 = new DummyToken();
        ManagerStandalone implementation =
            new ManagerStandalone(address(t1), Manager.Mode.LOCKING, chainId1, 1 days);

        managerChain1 = ManagerStandalone(address(new ERC1967Proxy(address(implementation), "")));
        managerChain1.initialize();

        WormholeEndpointStandalone wormholeEndpointChain1Implementation = new WormholeEndpointStandalone(
            address(managerChain1), 
            address(wormhole),
            address(relayer)
        );
        wormholeEndpointChain1 = WormholeEndpointStandalone(address(new ERC1967Proxy(address(wormholeEndpointChain1Implementation), "")));
        wormholeEndpointChain1.initialize();

        managerChain1.setEndpoint(address(wormholeEndpointChain1));
        managerChain1.setOutboundLimit(type(uint64).max);
        managerChain1.setInboundLimit(type(uint64).max, chainId2);

        // Chain 2 setup
        vm.chainId(chainId2);
        DummyToken t2 = new DummyTokenMintAndBurn();
        ManagerStandalone implementationChain2 =
            new ManagerStandalone(address(t2), Manager.Mode.BURNING, chainId2, 1 days);

        managerChain2 = ManagerStandalone(address(new ERC1967Proxy(address(implementationChain2), "")));
        managerChain2.initialize();

        WormholeEndpointStandalone wormholeEndpointChain2Implementation = new WormholeEndpointStandalone(
            address(managerChain2), 
            address(wormhole),
            address(relayer)
        );
        wormholeEndpointChain2 = WormholeEndpointStandalone(address(new ERC1967Proxy(address(wormholeEndpointChain2Implementation), "")));
        wormholeEndpointChain2.initialize();

        managerChain2.setEndpoint(address(wormholeEndpointChain2));
        managerChain2.setOutboundLimit(type(uint64).max);
        managerChain2.setInboundLimit(type(uint64).max, chainId1);

        // Register sibling contracts for the manager and endpoint. Endpoints and manager each have the concept of siblings here.
        managerChain1.setSibling(chainId2, bytes32(uint256(uint160(address(managerChain2)))));
        managerChain2.setSibling(chainId1, bytes32(uint256(uint160(address(managerChain1)))));

        // Set siblings for the endpoints
        wormholeEndpointChain1.setWormholeSibling(chainId2, bytes32(uint256(uint160(address(wormholeEndpointChain2)))));
        wormholeEndpointChain2.setWormholeSibling(chainId1, bytes32(uint256(uint160(address(wormholeEndpointChain1)))));

       //console.log(managerChain1.getThreshold());
    }

    function testChainToChainBase() public{
        managerChain1.setThreshold(1);
        managerChain2.setThreshold(1);
    
        vm.chainId(chainId1);

        // Setting up the transfer
        DummyToken token1 = DummyToken(managerChain1.token());
        DummyToken token2 = DummyTokenMintAndBurn(managerChain2.token());

        uint8 decimals = token1.decimals();
        uint256 sendingAmount = 5 * 10 ** decimals; 
        token1.mintDummy(address(userA), 5 * 10 ** decimals);
        vm.startPrank(userA);
        token1.approve(
            address(managerChain1),
            sendingAmount
        );

        vm.recordLogs();

        // Send token through standard means (not relayer) 
        {
            uint256 managerBalanceBefore = token1.balanceOf(address(managerChain1));
            uint256 userBalanceBefore = token1.balanceOf(address(userA));
            managerChain1.transfer(
                sendingAmount,
                chainId2,
                bytes32(uint256(uint160(userB))),
                false
            );

            // Balance check on funds going in and out working as expected
            uint256 managerBalanceAfter = token1.balanceOf(address(managerChain1));
            uint256 userBalanceAfter = token1.balanceOf(address(userB));
            require(managerBalanceBefore + sendingAmount == managerBalanceAfter, "Should be locking the tokens");
            require(userBalanceBefore - sendingAmount == userBalanceAfter, "User should have sent tokens");
        }

        vm.stopPrank();

        // Get and sign the log to go down the other pipe. Thank you to whoever wrote this code in the past!
        Vm.Log[] memory entries = guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        bytes[] memory encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = guardian.fetchSignedMessageFromLogs(
                entries[i], chainId1
            );
        }

        // Chain2 verification and checks 
        vm.chainId(chainId2);

        vm.expectRevert(); // Wrong chain receiving the signed VAA
        wormholeEndpointChain1.receiveMessage(encodedVMs[0]);
        {
            uint256 supplyBefore = token2.totalSupply();
            wormholeEndpointChain2.receiveMessage(encodedVMs[0]);
            uint256 supplyAfter = token2.totalSupply();

            require(sendingAmount + supplyBefore == supplyAfter, "Supplies dont match");
            require(token2.balanceOf(userB) == sendingAmount, "User didn't receive tokens");
            require(token2.balanceOf(address(managerChain2)) == 0, "Manager has unintended funds");
        }

        // Can't resubmit the same message twice
        vm.expectRevert(); // TransferAlreadyCompleted error
        wormholeEndpointChain2.receiveMessage(encodedVMs[0]);

        // Go back the other way from a THIRD user
        vm.prank(userB);
        token2.transfer(userC, sendingAmount);

        vm.startPrank(userC);
        token2.approve(address(managerChain2), sendingAmount);
        vm.recordLogs();

        // Supply checks on the transfer
        {
            uint256 supplyBefore = token2.totalSupply();
            managerChain2.transfer(
                sendingAmount,
                chainId1,
                bytes32(uint256(uint160(userD))),
                false
            ); 
            
            uint256 supplyAfter = token2.totalSupply();

            require(sendingAmount - supplyBefore == supplyAfter, "Supplies don't match");
            require(token2.balanceOf(userB) == 0, "OG user receive tokens");
            require(token2.balanceOf(userC) == 0, "Sending user didn't receive tokens");
            require(token2.balanceOf(address(managerChain2)) == 0, "Manager didn't receive unintended funds");
        }

        // Get and sign the log to go down the other pipe. Thank you to whoever wrote this code in the past!
        entries = guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = guardian.fetchSignedMessageFromLogs(
                entries[i], chainId2
            );
        }

        // Chain1 verification and checks with the receiving of the message
        vm.chainId(chainId1);

        {
            uint256 supplyBefore = token1.totalSupply();
            wormholeEndpointChain1.receiveMessage(encodedVMs[0]);

            uint256 supplyAfter = token1.totalSupply();

            require(supplyBefore == supplyAfter, "Supplies don't match between operations");
            require(token1.balanceOf(userB) == 0, "OG user receive tokens");
            require(token1.balanceOf(userC) == 0, "Sending user didn't receive tokens");
            require(token1.balanceOf(userD) == sendingAmount, "User received funds");
        }
    }

    function testLotsOfReverts() public{

        vm.chainId(chainId1);

        // Setting up the transfer
        DummyToken token1 = DummyToken(managerChain1.token());
        DummyToken token2 = DummyTokenMintAndBurn(managerChain2.token());

        uint8 decimals = token1.decimals();
        uint256 sendingAmount = 5 * 10 ** decimals; 
        token1.mintDummy(address(userA), 5 * 10 ** decimals);
        vm.startPrank(userA);
        token1.approve(
            address(managerChain1),
            sendingAmount
        );

        vm.recordLogs();
        
        // Send token through standard means (not relayer) 
        {
            uint256 managerBalanceBefore = token1.balanceOf(address(managerChain1));
            uint256 userBalanceBefore = token1.balanceOf(address(userA));
            managerChain1.transfer(
                sendingAmount,
                chainId2,
                bytes32(uint256(uint160(userB))),
                true
            );

            // Balance check on funds going in and out working as expected
            uint256 managerBalanceAfter = token1.balanceOf(address(managerChain1));
            uint256 userBalanceAfter = token1.balanceOf(address(userB));
            require(managerBalanceBefore + sendingAmount == managerBalanceAfter, "Should be locking the tokens");
            require(userBalanceBefore - sendingAmount == userBalanceAfter, "User should have sent tokens");
        }

        vm.stopPrank();

        // Get and sign the log to go down the other pipe. Thank you to whoever wrote this code in the past!
        Vm.Log[] memory entries = guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        bytes[] memory encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = guardian.fetchSignedMessageFromLogs(
                entries[i], chainId1
            );
        }

        vm.expectRevert(abi.encodeWithSelector(IWormholeEndpoint.InvalidWormholeSibling.selector, chainId1, wormholeEndpointChain1)); // Wrong chain receiving the signed VAA
        wormholeEndpointChain1.receiveMessage(encodedVMs[0]);

        vm.chainId(chainId2);
        //Chain2 verification and checks 
        //Threshold test - ensure that if the threshold is NOT set then we can't push anything through.
        //TODO - add test back in once the threshold will cause a 'revert' on transfer since it cannot be accepted. BUG here, since all TXs prior to the setting of the threshold above 0 are now LOCKED
        // {
        //     uint256 supplyBefore = token2.totalSupply();
        //     wormholeEndpointChain2.receiveMessage(encodedVMs[0]);
        //     uint256 supplyAfter = token2.totalSupply();

        //     require(supplyBefore == supplyAfter, "Supplies dont match");
        //     require(token2.balanceOf(userB) == 0, "User didn't receive tokens");
        //     require(token2.balanceOf(address(managerChain2)) == 0, "Manager has unintended funds");
        // }

        // Actually handle message since we have now set the threshold
        managerChain1.setThreshold(1);
        managerChain2.setThreshold(1);
        {
            uint256 supplyBefore = token2.totalSupply();
            wormholeEndpointChain2.receiveMessage(encodedVMs[0]);
            uint256 supplyAfter = token2.totalSupply();

            require(sendingAmount + supplyBefore == supplyAfter, "Supplies dont match");
            require(token2.balanceOf(userB) == sendingAmount, "User didn't receive tokens");
            require(token2.balanceOf(address(managerChain2)) == 0, "Manager has unintended funds");
        }



        // Can't resubmit the same message twice
        vm.expectRevert(); // TransferAlreadyCompleted error
        wormholeEndpointChain2.receiveMessage(encodedVMs[0]);


        // Go back the other way from a THIRD user
        vm.prank(userB);
        token2.transfer(userC, sendingAmount);

        vm.startPrank(userC);
        token2.approve(address(managerChain2), sendingAmount);
        vm.recordLogs();

        // Supply checks on the transfer
        {
            uint256 supplyBefore = token2.totalSupply();

            vm.stopPrank();
            managerChain2.setOutboundLimit(0);

            vm.startPrank(userC);
            managerChain2.transfer(
                sendingAmount,
                chainId1,
                bytes32(uint256(uint160(userD))),
                true
            ); 

            // Test timing on the queues
            vm.expectRevert();
            managerChain2.completeOutboundQueuedTransfer(0);
            vm.warp(vm.getBlockTimestamp() + 1 days-1);
            vm.expectRevert();
            managerChain2.completeOutboundQueuedTransfer(0);
            vm.warp(vm.getBlockTimestamp() + 1);
            managerChain2.completeOutboundQueuedTransfer(0);

            vm.expectRevert(); // Replay - should be deleted
            managerChain2.completeOutboundQueuedTransfer(0);

            vm.expectRevert(); // Non-existant
            managerChain2.completeOutboundQueuedTransfer(1);
            
            uint256 supplyAfter = token2.totalSupply();

            require(sendingAmount - supplyBefore == supplyAfter, "Supplies don't match");
            require(token2.balanceOf(userB) == 0, "OG user receive tokens");
            require(token2.balanceOf(userC) == 0, "Sending user didn't receive tokens");
            require(token2.balanceOf(address(managerChain2)) == 0, "Manager didn't receive unintended funds");
        }

        // Get and sign the log to go down the other pipe. Thank you to whoever wrote this code in the past!
        entries = guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = guardian.fetchSignedMessageFromLogs(
                entries[i], chainId2
            );
        }

        // Chain1 verification and checks with the receiving of the message
        vm.chainId(chainId1);
        vm.stopPrank(); // Back to the owner of everything for this one.

        {
            uint256 supplyBefore = token1.totalSupply();

            managerChain1.setInboundLimit(0, chainId2);
            wormholeEndpointChain1.receiveMessage(encodedVMs[0]);

            // TODO - get a specific event - InboundTransferQueued - and use this hash instead

            vm.warp(vm.getBlockTimestamp() + 100000);
            managerChain1.completeInboundQueuedTransfer(0xaec9ec1e50c5d68731ab3d17b9e7690c5fa900f94f2bd2315e92392499ae3f42);

            // Double redeem
            vm.warp(vm.getBlockTimestamp() + 100000);
            vm.expectRevert();
            managerChain1.completeInboundQueuedTransfer(0xaec9ec1e50c5d68731ab3d17b9e7690c5fa900f94f2bd2315e92392499ae3f42);

            uint256 supplyAfter = token1.totalSupply();

            require(supplyBefore == supplyAfter, "Supplies don't match between operations");
            require(token1.balanceOf(userB) == 0, "OG user receive tokens");
            require(token1.balanceOf(userC) == 0, "Sending user didn't receive tokens");
            require(token1.balanceOf(userD) == sendingAmount, "User received funds");
        }
     }

    function testMultiEndpoint() public {
        managerChain1.setThreshold(1);
        managerChain2.setThreshold(1);
 
        vm.chainId(chainId1);

        WormholeEndpointStandalone wormholeEndpointChain1_1 = wormholeEndpointChain1;

        // Dual endpoint setup 
        WormholeEndpointStandalone wormholeEndpointChain1_2 = new WormholeEndpointStandalone(
            address(managerChain1), 
            address(wormhole),
            address(relayer) 
        );

        wormholeEndpointChain1_2 = WormholeEndpointStandalone(address(new ERC1967Proxy(address(wormholeEndpointChain1_2), "")));
        wormholeEndpointChain1_2.initialize();

        vm.chainId(chainId2);
        WormholeEndpointStandalone wormholeEndpointChain2_1 = wormholeEndpointChain2;

        // Dual endpoint setup 
        WormholeEndpointStandalone wormholeEndpointChain2_2 = new WormholeEndpointStandalone(
            address(managerChain2), 
            address(wormhole),
            address(relayer) 
        );

        wormholeEndpointChain2_2 = WormholeEndpointStandalone(address(new ERC1967Proxy(address(wormholeEndpointChain2_2), "")));
        wormholeEndpointChain2_2.initialize();

        // Setup the new entrypoint hook ups to allow the transfers to occur
        wormholeEndpointChain1_2.setWormholeSibling(chainId2, bytes32(uint256(uint160((address(wormholeEndpointChain2_2))))));
        wormholeEndpointChain2_2.setWormholeSibling(chainId1, bytes32(uint256(uint160((address(wormholeEndpointChain1_2))))));
        managerChain2.setEndpoint(address(wormholeEndpointChain2_2));
        managerChain1.setEndpoint(address(wormholeEndpointChain1_2));

        // Change the threshold from the setUp functions 1 to 2.
        managerChain1.setThreshold(2);
        managerChain2.setThreshold(2);
 
        // Setting up the transfer
        DummyToken token1 = DummyToken(managerChain1.token());
        DummyToken token2 = DummyTokenMintAndBurn(managerChain2.token()); 

        vm.startPrank(userA);
        uint8 decimals = token1.decimals();
        uint256 sendingAmount = 5 * 10 ** decimals; 
        token1.mintDummy(address(userA), sendingAmount);
        vm.startPrank(userA);
        token1.approve(
            address(managerChain1),
            sendingAmount
        );

        vm.recordLogs();

        // Send token through standard means (not relayer) 
        {
            uint256 managerBalanceBefore = token1.balanceOf(address(managerChain1));
            uint256 userBalanceBefore = token1.balanceOf(address(userA));
            managerChain1.transfer(
                sendingAmount,
                chainId2,
                bytes32(uint256(uint160(userB))),
                false
            );
        }

        // Get and sign the event emissions to go to the other chain.
        Vm.Log[] memory entries = guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        bytes[] memory encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = guardian.fetchSignedMessageFromLogs(
                entries[i], chainId1
            );
        }


        vm.chainId(chainId2);

        // Send in the messages for the two endpoints to complete the transfer from chain1 to chain2
        {
            // vm.stopPrank();
            uint256 supplyBefore = token2.totalSupply();
            wormholeEndpointChain2_1.receiveMessage(encodedVMs[0]);

            vm.expectRevert(); // Invalid wormhole sibling
            wormholeEndpointChain2_2.receiveMessage(encodedVMs[0]);

            // Threshold check
            require(supplyBefore == token2.totalSupply(), "Supplies have been updated too early");
            require(token2.balanceOf(userB) == 0, "User received tokens to early");

            // Finish the transfer out once the second VAA arrives
            wormholeEndpointChain2_2.receiveMessage(encodedVMs[1]);
            uint256 supplyAfter = token2.totalSupply();

            require(sendingAmount + supplyBefore == supplyAfter, "Supplies dont match");
            require(token2.balanceOf(userB) == sendingAmount, "User didn't receive tokens");
            require(token2.balanceOf(address(managerChain2)) == 0, "Manager has unintended funds");
        }

        // Back the other way for the burn!
        vm.startPrank(userB);
        token2.approve(
            address(managerChain2),
            sendingAmount
        );

        vm.recordLogs();

        // Send token through standard means (not relayer) 
        {
            uint256 userBalanceBefore = token1.balanceOf(address(userB));
            managerChain2.transfer(
                sendingAmount,
                chainId1,
                bytes32(uint256(uint160(userA))),
                false
            );
            uint256 managerBalanceAfter = token1.balanceOf(address(managerChain2));
            uint256 userBalanceAfter= token1.balanceOf(address(userB));

            require(userBalanceBefore - userBalanceAfter == 0, "No funds left for user");
            require(managerBalanceAfter == 0, "Manager should burn all tranferred tokens");
        }

        // Get the VAA proof for the transfers to use
        entries = guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = guardian.fetchSignedMessageFromLogs(
                entries[i], chainId2
            );
        }

        vm.chainId(chainId1);
        {
            uint256 supplyBefore = token1.totalSupply();
            wormholeEndpointChain1_1.receiveMessage(encodedVMs[0]);

            require(supplyBefore == token1.totalSupply(), "Supplies have been updated too early");
            require(token2.balanceOf(userA) == 0, "User received tokens to early");

            // Finish the transfer out once the second VAA arrives
            wormholeEndpointChain1_2.receiveMessage(encodedVMs[1]);
            uint256 supplyAfter = token1.totalSupply();

            require(supplyBefore == supplyAfter, "Supplies don't match between operations. Should not increase.");
            require(token1.balanceOf(userB) == 0, "Sending user receive tokens");
            require(token1.balanceOf(userA) == sendingAmount, "Receiving user didn't receive tokens");
        }

        vm.stopPrank();
    }

    function copyBytes(bytes memory _bytes) private pure returns (bytes memory)
    {
        bytes memory copy = new bytes(_bytes.length);
        uint256 max = _bytes.length + 31;
        for (uint256 i=32; i<=max; i+=32)
        {
            assembly { mstore(add(copy, i), mload(add(_bytes, i))) }
        }
        return copy;
    }
}
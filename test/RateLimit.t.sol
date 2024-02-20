// // SPDX-License-Identifier: Apache 2

// import "forge-std/Test.sol";
// import "../src/interfaces/IRateLimiterEvents.sol";
// import "../src/ManagerStandalone.sol";
// import "./mocks/DummyEndpoint.sol";
// import "./mocks/DummyToken.sol";
// import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
// import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import "./libraries/EndpointHelpers.sol";
// import "./libraries/ManagerHelpers.sol";

// pragma solidity >=0.8.8 <0.9.0;

// contract TestRateLimit is Test, IRateLimiterEvents {
//     ManagerStandalone manager;

//     using NormalizedAmountLib for uint256;
//     using NormalizedAmountLib for NormalizedAmount;

//     uint16 constant chainId = 7;

//     uint256 constant DEVNET_GUARDIAN_PK =
//         0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
//     WormholeSimulator guardian;
//     uint256 initialBlockTimestamp;

//     function setUp() public {
//         string memory url = "https://ethereum-goerli.publicnode.com";
//         IWormhole wormhole = IWormhole(0x706abc4E45D419950511e474C7B9Ed348A4a716c);
//         vm.createSelectFork(url);
//         initialBlockTimestamp = vm.getBlockTimestamp();

//         guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);

//         DummyToken t = new DummyToken();
//         ManagerStandalone implementation =
//             new ManagerStandalone(address(t), Manager.Mode.LOCKING, chainId, 1 days);

//         manager = ManagerStandalone(address(new ERC1967Proxy(address(implementation), "")));
//         manager.initialize();
//     }

//     function test_outboundRateLimit_setLimitSimple() public {
//         DummyToken token = DummyToken(manager.token());
//         uint8 decimals = token.decimals();

//         uint256 limit = 1 * 10 ** 6;
//         manager.setOutboundLimit(limit);

//         IRateLimiter.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

//         assertEq(outboundLimitParams.limit.getAmount(), limit.normalize(decimals).getAmount());
//         assertEq(
//             outboundLimitParams.currentCapacity.getAmount(), limit.normalize(decimals).getAmount()
//         );
//         assertEq(outboundLimitParams.lastTxTimestamp, initialBlockTimestamp);
//     }

//     function test_outboundRateLimit() public {
//         // transfer 3 tokens
//         address user_A = address(0x123);
//         address user_B = address(0x456);

//         DummyToken token = DummyToken(manager.token());

//         uint8 decimals = token.decimals();

//         token.mintDummy(address(user_A), 5 * 10 ** decimals);
//         uint256 outboundLimit = 4 * 10 ** decimals;
//         manager.setOutboundLimit(outboundLimit);

//         vm.startPrank(user_A);

//         uint256 transferAmount = 3 * 10 ** decimals;
//         token.approve(address(manager), transferAmount);
//         manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false, new bytes(1));

//         vm.stopPrank();

//         // assert outbound rate limit was updated
//         IRateLimiter.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();
//         assertEq(
//             outboundLimitParams.currentCapacity.getAmount(),
//             (outboundLimit - transferAmount).normalize(decimals).getAmount()
//         );
//         assertEq(outboundLimitParams.lastTxTimestamp, initialBlockTimestamp);

//         // assert inbound rate limit for destination chain is still at the max.
//         // the backflow should not override the limit.
//         IRateLimiter.RateLimitParams memory inboundLimitParams =
//             manager.getInboundLimitParams(chainId);
//         assertEq(
//             inboundLimitParams.currentCapacity.getAmount(), inboundLimitParams.limit.getAmount()
//         );
//         assertEq(inboundLimitParams.lastTxTimestamp, initialBlockTimestamp);
//     }

//     function test_outboundRateLimit_setHigherLimit() public {
//         // transfer 3 tokens
//         address user_A = address(0x123);
//         address user_B = address(0x456);

//         DummyToken token = DummyToken(manager.token());

//         uint8 decimals = token.decimals();

//         token.mintDummy(address(user_A), 5 * 10 ** decimals);
//         uint256 outboundLimit = 4 * 10 ** decimals;
//         manager.setOutboundLimit(outboundLimit);

//         vm.startPrank(user_A);

//         uint256 transferAmount = 3 * 10 ** decimals;
//         token.approve(address(manager), transferAmount);
//         manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false, new bytes(1));

//         vm.stopPrank();

//         // update the outbound limit to 5 tokens
//         vm.startPrank(address(this));

//         uint256 higherLimit = 5 * 10 ** decimals;
//         manager.setOutboundLimit(higherLimit);

//         IRateLimiter.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

//         assertEq(outboundLimitParams.limit.getAmount(), higherLimit.normalize(decimals).getAmount());
//         assertEq(outboundLimitParams.lastTxTimestamp, initialBlockTimestamp);
//         assertEq(
//             outboundLimitParams.currentCapacity.getAmount(),
//             (2 * 10 ** decimals).normalize(decimals).getAmount()
//         );
//     }

//     function test_outboundRateLimit_setLowerLimit() public {
//         // transfer 3 tokens
//         address user_A = address(0x123);
//         address user_B = address(0x456);

//         DummyToken token = DummyToken(manager.token());

//         uint8 decimals = token.decimals();

//         token.mintDummy(address(user_A), 5 * 10 ** decimals);
//         uint256 outboundLimit = 4 * 10 ** decimals;
//         manager.setOutboundLimit(outboundLimit);

//         vm.startPrank(user_A);

//         uint256 transferAmount = 3 * 10 ** decimals;
//         token.approve(address(manager), transferAmount);
//         manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false, new bytes(1));

//         vm.stopPrank();

//         // update the outbound limit to 5 tokens
//         vm.startPrank(address(this));

//         uint256 lowerLimit = 2 * 10 ** decimals;
//         manager.setOutboundLimit(lowerLimit);

//         IRateLimiter.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

//         assertEq(outboundLimitParams.limit.denormalize(decimals), lowerLimit);
//         assertEq(outboundLimitParams.lastTxTimestamp, initialBlockTimestamp);
//         assertEq(outboundLimitParams.currentCapacity.getAmount(), 0);
//     }

//     function test_outboundRateLimit_setHigherLimit_duration() public {
//         // transfer 3 tokens
//         address user_A = address(0x123);
//         address user_B = address(0x456);

//         DummyToken token = DummyToken(manager.token());

//         uint8 decimals = token.decimals();

//         token.mintDummy(address(user_A), 5 * 10 ** decimals);
//         uint256 outboundLimit = 4 * 10 ** decimals;
//         manager.setOutboundLimit(outboundLimit);

//         vm.startPrank(user_A);

//         uint256 transferAmount = 3 * 10 ** decimals;
//         token.approve(address(manager), transferAmount);
//         manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false, new bytes(1));

//         vm.stopPrank();

//         // change block timestamp to be 6 hours later
//         uint256 sixHoursLater = initialBlockTimestamp + 6 hours;
//         vm.warp(sixHoursLater);

//         // update the outbound limit to 5 tokens
//         vm.startPrank(address(this));

//         uint256 higherLimit = 5 * 10 ** decimals;
//         manager.setOutboundLimit(higherLimit);

//         IRateLimiter.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

//         assertEq(outboundLimitParams.limit.getAmount(), higherLimit.normalize(decimals).getAmount());
//         assertEq(outboundLimitParams.lastTxTimestamp, sixHoursLater);
//         // capacity should be:
//         // difference in limits + remaining capacity after t1 + the amount that's refreshed (based on the old rps)
//         assertEq(
//             outboundLimitParams.currentCapacity.getAmount(),
//             (
//                 (1 * 10 ** decimals) + (1 * 10 ** decimals)
//                     + (outboundLimit * (6 hours)) / manager.rateLimitDuration()
//             ).normalize(decimals).getAmount()
//         );
//     }

//     function test_outboundRateLimit_setLowerLimit_durationCaseOne() public {
//         // transfer 3 tokens
//         address user_A = address(0x123);
//         address user_B = address(0x456);

//         DummyToken token = DummyToken(manager.token());

//         uint8 decimals = token.decimals();

//         token.mintDummy(address(user_A), 5 * 10 ** decimals);
//         uint256 outboundLimit = 5 * 10 ** decimals;
//         manager.setOutboundLimit(outboundLimit);

//         vm.startPrank(user_A);

//         uint256 transferAmount = 4 * 10 ** decimals;
//         token.approve(address(manager), transferAmount);
//         manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false, new bytes(1));

//         vm.stopPrank();

//         // change block timestamp to be 6 hours later
//         uint256 sixHoursLater = initialBlockTimestamp + 3 hours;
//         vm.warp(sixHoursLater);

//         // update the outbound limit to 3 tokens
//         vm.startPrank(address(this));

//         uint256 lowerLimit = 3 * 10 ** decimals;
//         manager.setOutboundLimit(lowerLimit);

//         IRateLimiter.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

//         assertEq(outboundLimitParams.limit.getAmount(), lowerLimit.normalize(decimals).getAmount());
//         assertEq(outboundLimitParams.lastTxTimestamp, sixHoursLater);
//         // capacity should be: 0
//         assertEq(outboundLimitParams.currentCapacity.getAmount(), 0);
//     }

//     function test_outboundRateLimit_setLowerLimit_durationCaseTwo() public {
//         address user_A = address(0x123);
//         address user_B = address(0x456);

//         DummyToken token = DummyToken(manager.token());

//         uint8 decimals = token.decimals();

//         token.mintDummy(address(user_A), 5 * 10 ** decimals);
//         // set the outbound limit to 5 tokens
//         uint256 outboundLimit = 5 * 10 ** decimals;
//         manager.setOutboundLimit(outboundLimit);

//         vm.startPrank(user_A);

//         // transfer 2 tokens
//         uint256 transferAmount = 2 * 10 ** decimals;
//         token.approve(address(manager), transferAmount);
//         manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false, new bytes(1));

//         vm.stopPrank();

//         // change block timestamp to be 6 hours later
//         uint256 sixHoursLater = initialBlockTimestamp + 6 hours;
//         vm.warp(sixHoursLater);

//         vm.startPrank(address(this));

//         // update the outbound limit to 4 tokens
//         uint256 lowerLimit = 4 * 10 ** decimals;
//         manager.setOutboundLimit(lowerLimit);

//         IRateLimiter.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

//         assertEq(outboundLimitParams.limit.getAmount(), lowerLimit.normalize(decimals).getAmount());
//         assertEq(outboundLimitParams.lastTxTimestamp, sixHoursLater);
//         // capacity should be:
//         // remaining capacity after t1 - difference in limits + the amount that's refreshed (based on the old rps)
//         assertEq(
//             outboundLimitParams.currentCapacity.getAmount(),
//             (
//                 (3 * 10 ** decimals) - (1 * 10 ** decimals)
//                     + (outboundLimit * (6 hours)) / manager.rateLimitDuration()
//             ).normalize(decimals).getAmount()
//         );
//     }

//     function test_outboundRateLimit_singleHit() public {
//         address user_A = address(0x123);
//         address user_B = address(0x456);

//         DummyToken token = DummyToken(manager.token());

//         uint8 decimals = token.decimals();

//         token.mintDummy(address(user_A), 5 * 10 ** decimals);
//         uint256 outboundLimit = 1 * 10 ** decimals;
//         manager.setOutboundLimit(outboundLimit);

//         vm.startPrank(user_A);

//         uint256 transferAmount = 3 * 10 ** decimals;
//         token.approve(address(manager), transferAmount);

//         bytes4 selector = bytes4(keccak256("NotEnoughCapacity(uint256,uint256)"));
//         vm.expectRevert(abi.encodeWithSelector(selector, outboundLimit, transferAmount));
//         manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false, new bytes(1));
//     }

//     function test_outboundRateLimit_multiHit() public {
//         address user_A = address(0x123);
//         address user_B = address(0x456);

//         DummyToken token = DummyToken(manager.token());

//         uint8 decimals = token.decimals();

//         token.mintDummy(address(user_A), 5 * 10 ** decimals);
//         uint256 outboundLimit = 4 * 10 ** decimals;
//         manager.setOutboundLimit(outboundLimit);

//         vm.startPrank(user_A);

//         uint256 transferAmount = 3 * 10 ** decimals;
//         token.approve(address(manager), transferAmount);
//         manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false, new bytes(1));

//         // assert that first transfer went through
//         assertEq(token.balanceOf(address(user_A)), 2 * 10 ** decimals);
//         assertEq(token.balanceOf(address(manager)), transferAmount);

//         // assert currentCapacity is updated
//         NormalizedAmount memory newCapacity =
//             outboundLimit.normalize(decimals).sub(transferAmount.normalize(decimals));
//         assertEq(manager.getCurrentOutboundCapacity(), newCapacity.denormalize(decimals));

//         uint256 badTransferAmount = 2 * 10 ** decimals;
//         token.approve(address(manager), badTransferAmount);

//         bytes4 selector = bytes4(keccak256("NotEnoughCapacity(uint256,uint256)"));
//         vm.expectRevert(
//             abi.encodeWithSelector(selector, newCapacity.denormalize(decimals), badTransferAmount)
//         );
//         manager.transfer(badTransferAmount, chainId, toWormholeFormat(user_B), false, new bytes(1));
//     }

//     // make a transfer with shouldQueue == true
//     // check that it hits rate limit and gets inserted into the queue
//     // test that it remains in queue after < rateLimitDuration
//     // test that it exits queue after >= rateLimitDuration
//     // test that it's removed from queue and can't be replayed
//     function test_outboundRateLimit_queue() public {
//         address user_A = address(0x123);
//         address user_B = address(0x456);

//         DummyToken token = DummyToken(manager.token());

//         uint8 decimals = token.decimals();

//         token.mintDummy(address(user_A), 5 * 10 ** decimals);
//         uint256 outboundLimit = 4 * 10 ** decimals;
//         manager.setOutboundLimit(outboundLimit);

//         vm.startPrank(user_A);

//         uint256 transferAmount = 5 * 10 ** decimals;
//         token.approve(address(manager), transferAmount);

//         // transfer with shouldQueue == true
//         uint64 qSeq =
//             manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), true, new bytes(1));

//         // assert that the transfer got queued up
//         assertEq(qSeq, 0);
//         IRateLimiter.OutboundQueuedTransfer memory qt = manager.getOutboundQueuedTransfer(0);
//         assertEq(qt.amount.getAmount(), transferAmount.normalize(decimals).getAmount());
//         assertEq(qt.recipientChain, chainId);
//         assertEq(qt.recipient, toWormholeFormat(user_B));
//         assertEq(qt.txTimestamp, initialBlockTimestamp);

//         // assert that the contract also locked funds from the user
//         assertEq(token.balanceOf(address(user_A)), 0);
//         assertEq(token.balanceOf(address(manager)), transferAmount);

//         // elapse rate limit duration - 1
//         uint256 durationElapsedTime = initialBlockTimestamp + manager.rateLimitDuration();
//         vm.warp(durationElapsedTime - 1);

//         // assert that transfer still can't be completed
//         bytes4 stillQueuedSelector =
//             bytes4(keccak256("OutboundQueuedTransferStillQueued(uint64,uint256)"));
//         vm.expectRevert(abi.encodeWithSelector(stillQueuedSelector, 0, initialBlockTimestamp));
//         manager.completeOutboundQueuedTransfer(0);

//         // now complete transfer
//         vm.warp(durationElapsedTime);
//         uint64 seq = manager.completeOutboundQueuedTransfer(0);
//         assertEq(seq, 0);

//         // now ensure transfer was removed from queue
//         bytes4 notFoundSelector = bytes4(keccak256("OutboundQueuedTransferNotFound(uint64)"));
//         vm.expectRevert(abi.encodeWithSelector(notFoundSelector, 0));
//         manager.completeOutboundQueuedTransfer(0);
//     }

//     function test_inboundRateLimit_simple() public {
//         address user_B = address(0x456);

//         (DummyEndpoint e1, DummyEndpoint e2) = EndpointHelpersLib.setup_endpoints(manager);

//         DummyToken token = DummyToken(manager.token());

//         IEndpointReceiver[] memory endpoints = new IEndpointReceiver[](2);
//         endpoints[0] = e1;
//         endpoints[1] = e2;

//         NormalizedAmount memory transferAmount = NormalizedAmount(50, 8);
//         NormalizedAmount memory limitAmount = NormalizedAmount(100, 8);
//         EndpointHelpersLib.attestEndpointsHelper(
//             user_B, 0, chainId, manager, transferAmount, limitAmount, endpoints
//         );

//         // assert that the user received tokens
//         assertEq(token.balanceOf(address(user_B)), transferAmount.denormalize(token.decimals()));

//         // assert that the inbound limits updated
//         IRateLimiter.RateLimitParams memory inboundLimitParams =
//             manager.getInboundLimitParams(EndpointHelpersLib.SENDING_CHAIN_ID);
//         assertEq(
//             inboundLimitParams.currentCapacity.getAmount(),
//             limitAmount.sub(transferAmount).getAmount()
//         );
//         assertEq(inboundLimitParams.lastTxTimestamp, initialBlockTimestamp);

//         // assert that the outbound limit is still at the max
//         // backflow should not go over the max limit
//         IRateLimiter.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();
//         assertEq(
//             outboundLimitParams.currentCapacity.getAmount(), outboundLimitParams.limit.getAmount()
//         );
//         assertEq(outboundLimitParams.lastTxTimestamp, initialBlockTimestamp);
//     }

//     function test_inboundRateLimit_queue() public {
//         address user_B = address(0x456);

//         (DummyEndpoint e1, DummyEndpoint e2) = EndpointHelpersLib.setup_endpoints(manager);

//         DummyToken token = DummyToken(manager.token());

//         IEndpointReceiver[] memory endpoints = new IEndpointReceiver[](1);
//         endpoints[0] = e1;

//         EndpointStructs.ManagerMessage memory m;
//         bytes memory encodedEm;
//         {
//             EndpointStructs.EndpointMessage memory em;
//             (m, em) = EndpointHelpersLib.attestEndpointsHelper(
//                 user_B,
//                 0,
//                 chainId,
//                 manager,
//                 NormalizedAmount(50, 8),
//                 uint256(5).normalize(token.decimals()),
//                 endpoints
//             );
//             encodedEm = EndpointStructs.encodeEndpointMessage(
//                 EndpointHelpersLib.TEST_ENDPOINT_PAYLOAD_PREFIX, em
//             );
//         }

//         bytes32 digest =
//             EndpointStructs.managerMessageDigest(EndpointHelpersLib.SENDING_CHAIN_ID, m);

//         // no quorum yet
//         assertEq(token.balanceOf(address(user_B)), 0);

//         vm.expectEmit(address(manager));
//         emit InboundTransferQueued(digest);
//         e2.receiveMessage(encodedEm);

//         {
//             // now we have quorum but it'll hit limit
//             IRateLimiter.InboundQueuedTransfer memory qt = manager.getInboundQueuedTransfer(digest);
//             assertEq(qt.amount.getAmount(), 50);
//             assertEq(qt.txTimestamp, initialBlockTimestamp);
//             assertEq(qt.recipient, user_B);
//         }

//         // assert that the user doesn't have funds yet
//         assertEq(token.balanceOf(address(user_B)), 0);

//         // change block time to (duration - 1) seconds later
//         uint256 durationElapsedTime = initialBlockTimestamp + manager.rateLimitDuration();
//         vm.warp(durationElapsedTime - 1);

//         {
//             // assert that transfer still can't be completed
//             bytes4 stillQueuedSelector =
//                 bytes4(keccak256("InboundQueuedTransferStillQueued(bytes32,uint256)"));
//             vm.expectRevert(
//                 abi.encodeWithSelector(stillQueuedSelector, digest, initialBlockTimestamp)
//             );
//             manager.completeInboundQueuedTransfer(digest);
//         }

//         // now complete transfer
//         vm.warp(durationElapsedTime);
//         manager.completeInboundQueuedTransfer(digest);

//         {
//             // assert transfer no longer in queue
//             bytes4 notQueuedSelector = bytes4(keccak256("InboundQueuedTransferNotFound(bytes32)"));
//             vm.expectRevert(abi.encodeWithSelector(notQueuedSelector, digest));
//             manager.completeInboundQueuedTransfer(digest);
//         }

//         // assert user now has funds
//         assertEq(token.balanceOf(address(user_B)), 50 * 10 ** (token.decimals() - 8));

//         // replay protection
//         vm.recordLogs();
//         e2.receiveMessage(encodedEm);

//         {
//             Vm.Log[] memory entries = vm.getRecordedLogs();
//             assertEq(entries.length, 2);
//             assertEq(entries[1].topics.length, 3);
//             assertEq(entries[1].topics[0], keccak256("MessageAlreadyExecuted(bytes32,bytes32)"));
//             assertEq(entries[1].topics[1], toWormholeFormat(address(manager)));
//             assertEq(
//                 entries[1].topics[2],
//                 EndpointStructs.managerMessageDigest(EndpointHelpersLib.SENDING_CHAIN_ID, m)
//             );
//         }
//     }

//     function test_circular_flow() public {
//         address user_A = address(0x123);
//         address user_B = address(0x456);

//         DummyToken token = DummyToken(manager.token());

//         uint8 decimals = token.decimals();

//         NormalizedAmount memory mintAmount = NormalizedAmount(50, 8);
//         token.mintDummy(address(user_A), mintAmount.denormalize(decimals));
//         manager.setOutboundLimit(mintAmount.denormalize(decimals));

//         // transfer 10 tokens
//         vm.startPrank(user_A);

//         NormalizedAmount memory transferAmount = NormalizedAmount(10, 8);
//         token.approve(address(manager), type(uint256).max);
//         manager.transfer(
//             transferAmount.denormalize(decimals),
//             chainId,
//             toWormholeFormat(user_B),
//             false,
//             new bytes(1)
//         );

//         vm.stopPrank();

//         // assert manager has 10 tokens and user_A has 10 fewer tokens
//         assertEq(token.balanceOf(address(manager)), transferAmount.denormalize(decimals));
//         assertEq(token.balanceOf(user_A), mintAmount.sub(transferAmount).denormalize(decimals));

//         {
//             // assert outbound rate limit decreased
//             IRateLimiter.RateLimitParams memory outboundLimitParams =
//                 manager.getOutboundLimitParams();
//             assertEq(
//                 outboundLimitParams.currentCapacity.getAmount(),
//                 outboundLimitParams.limit.sub(transferAmount).getAmount()
//             );
//             assertEq(outboundLimitParams.lastTxTimestamp, initialBlockTimestamp);
//         }

//         // go 1 second into the future
//         uint256 receiveTime = initialBlockTimestamp + 1;
//         vm.warp(receiveTime);

//         // now receive 10 tokens from user_B -> user_A
//         (DummyEndpoint e1, DummyEndpoint e2) = EndpointHelpersLib.setup_endpoints(manager);

//         IEndpointReceiver[] memory endpoints = new IEndpointReceiver[](2);
//         endpoints[0] = e1;
//         endpoints[1] = e2;

//         EndpointHelpersLib.attestEndpointsHelper(
//             user_A, 0, chainId, manager, transferAmount, mintAmount, endpoints
//         );

//         // assert that user_A has original amount
//         assertEq(token.balanceOf(user_A), mintAmount.denormalize(decimals));

//         {
//             // assert that the inbound limits decreased
//             IRateLimiter.RateLimitParams memory inboundLimitParams =
//                 manager.getInboundLimitParams(EndpointHelpersLib.SENDING_CHAIN_ID);
//             assertEq(
//                 inboundLimitParams.currentCapacity.getAmount(),
//                 inboundLimitParams.limit.sub(transferAmount).getAmount()
//             );
//             assertEq(inboundLimitParams.lastTxTimestamp, receiveTime);
//         }

//         {
//             // assert that outbound limit is at max again (because of backflow)
//             IRateLimiter.RateLimitParams memory outboundLimitParams =
//                 manager.getOutboundLimitParams();
//             assertEq(
//                 outboundLimitParams.currentCapacity.getAmount(),
//                 outboundLimitParams.limit.getAmount()
//             );
//             assertEq(outboundLimitParams.lastTxTimestamp, receiveTime);
//         }

//         // go 1 second into the future
//         uint256 sendAgainTime = receiveTime + 1;
//         vm.warp(sendAgainTime);

//         // transfer 10 back to the contract
//         vm.startPrank(user_A);

//         manager.transfer(
//             transferAmount.denormalize(decimals),
//             EndpointHelpersLib.SENDING_CHAIN_ID,
//             toWormholeFormat(user_B),
//             false,
//             new bytes(1)
//         );

//         vm.stopPrank();

//         {
//             // assert outbound rate limit decreased
//             IRateLimiter.RateLimitParams memory outboundLimitParams =
//                 manager.getOutboundLimitParams();
//             assertEq(
//                 outboundLimitParams.currentCapacity.getAmount(),
//                 outboundLimitParams.limit.sub(transferAmount).getAmount()
//             );
//             assertEq(outboundLimitParams.lastTxTimestamp, sendAgainTime);
//         }

//         {
//             // assert that the inbound limit is at max again (because of backflow)
//             IRateLimiter.RateLimitParams memory inboundLimitParams =
//                 manager.getInboundLimitParams(EndpointHelpersLib.SENDING_CHAIN_ID);
//             assertEq(
//                 inboundLimitParams.currentCapacity.getAmount(), inboundLimitParams.limit.getAmount()
//             );
//             assertEq(inboundLimitParams.lastTxTimestamp, sendAgainTime);
//         }
//     }
// }

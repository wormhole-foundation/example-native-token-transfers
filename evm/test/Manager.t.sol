// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "forge-std/Test.sol";

import "../src/ManagerStandalone.sol";
import "../src/EndpointStandalone.sol";
import "../src/interfaces/IManager.sol";
import "../src/interfaces/IManagerEvents.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// @dev A non-abstract EndpointManager contract
contract ManagerContract is ManagerStandalone {
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint256 rateLimitDuration
    ) ManagerStandalone(token, mode, chainId, rateLimitDuration) {}

    /// We create a dummy storage variable here with standard solidity slot assignment.
    /// Then we check that its assigned slot is 0, i.e. that the super contract doesn't
    /// define any storage variables (and instead uses deterministic slots).
    /// See `test_noAutomaticSlot` below.
    uint256 my_slot;

    function lastSlot() public pure returns (bytes32 result) {
        assembly ("memory-safe") {
            result := my_slot.slot
        }
    }
}

contract DummyEndpoint is EndpointStandalone {
    constructor(address manager) EndpointStandalone(manager) {}

    function _quoteDeliveryPrice(uint16 /* recipientChain */ )
        internal
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function _sendMessage(uint16 recipientChain, bytes memory payload) internal pure override {
        // do nothing
    }

    function _verifyMessage(bytes memory encodedMessage)
        internal
        pure
        override
        returns (bytes memory)
    {
        return encodedMessage;
    }
}

contract DummyToken is ERC20 {
    constructor() ERC20("DummyToken", "DTKN") {}

    // NOTE: this is purposefully not called mint() to so we can test that in
    // locking mode the EndpointManager contract doesn't call mint (or burn)
    function mintDummy(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// TODO: set this up so the common functionality tests can be run against both
// the standalone and the integrated version of the endpoint manager
contract TestManager is Test, IManagerEvents {
    ManagerStandalone manager;
    uint16 constant chainId = 7;

    function setUp() public {
        DummyToken t = new DummyToken();
        manager = new ManagerContract(address(t), Manager.Mode.LOCKING, chainId, 1 days);
        manager.initialize();
        // deploy sample token contract
        // deploy wormhole contract
        // wormhole = deployWormholeForTest();
        // deploy endpoint contracts
        // instantiate endpoint manager contract
        // endpointManager = new EndpointManagerContract();
    }

    // === pure unit tests

    function test_countSetBits() public {
        assertEq(manager.countSetBits(5), 2);
        assertEq(manager.countSetBits(0), 0);
        assertEq(manager.countSetBits(15), 4);
        assertEq(manager.countSetBits(16), 1);
        assertEq(manager.countSetBits(65535), 16);
    }

    // === ownership

    function test_owner() public {
        // TODO: implement separate governance contract
        assertEq(manager.owner(), address(this));
    }

    function test_transferOwnership() public {
        address newOwner = address(0x123);
        manager.transferOwnership(newOwner);
        assertEq(manager.owner(), newOwner);
    }

    function test_onlyOwnerCanTransferOwnership() public {
        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, notOwner));
        manager.transferOwnership(address(0x456));
    }

    // === endpoint registration

    function test_registerEndpoint() public {
        DummyEndpoint e = new DummyEndpoint(address(manager));
        manager.setEndpoint(address(e));
    }

    function test_onlyOwnerCanModifyEndpoints() public {
        DummyEndpoint e = new DummyEndpoint(address(manager));
        manager.setEndpoint(address(e));

        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, notOwner));
        manager.setEndpoint(address(e));

        vm.expectRevert(abi.encodeWithSelector(selector, notOwner));
        manager.removeEndpoint(address(e));
    }

    function test_cantEnableEndpointTwice() public {
        DummyEndpoint e = new DummyEndpoint(address(manager));
        manager.setEndpoint(address(e));

        bytes4 selector = bytes4(keccak256("EndpointAlreadyEnabled(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(e)));
        manager.setEndpoint(address(e));
    }

    function test_disableReenableEndpoint() public {
        DummyEndpoint e = new DummyEndpoint(address(manager));
        manager.setEndpoint(address(e));
        manager.removeEndpoint(address(e));
        manager.setEndpoint(address(e));
    }

    function test_multipleEndpoints() public {
        DummyEndpoint e1 = new DummyEndpoint(address(manager));
        DummyEndpoint e2 = new DummyEndpoint(address(manager));

        manager.setEndpoint(address(e1));
        manager.setEndpoint(address(e2));
    }

    function test_endpointIncompatibleManager() public {
        // TODO: this is accepted currently. should we include a check to ensure
        // only endpoints whose manager is us can be registered? (this would be
        // a convenience check, not a security one)
        DummyEndpoint e = new DummyEndpoint(address(0xBEEF));
        manager.setEndpoint(address(e));
    }

    function test_notEndpoint() public {
        // TODO: this is accepted currently. should we include a check to ensure
        // only endpoints can be registered? (this would be a convenience check, not a security one)
        manager.setEndpoint(address(0x123));
    }

    // == threshold

    function test_cantSetThresholdTooHigh() public {
        // no endpoints set, so can't set threshold to 1
        bytes4 selector = bytes4(keccak256("ThresholdTooHigh(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 1, 0));
        manager.setThreshold(1);
    }

    function test_canSetThreshold() public {
        DummyEndpoint e1 = new DummyEndpoint(address(manager));
        DummyEndpoint e2 = new DummyEndpoint(address(manager));
        manager.setEndpoint(address(e1));
        manager.setEndpoint(address(e2));

        manager.setThreshold(1);
        manager.setThreshold(2);
        manager.setThreshold(1);
    }

    function test_cantSetThresholdToZero() public {
        DummyEndpoint e = new DummyEndpoint(address(manager));
        manager.setEndpoint(address(e));

        bytes4 selector = bytes4(keccak256("ZeroThreshold()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        manager.setThreshold(0);
    }

    function test_onlyOwnerCanSetThreshold() public {
        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, notOwner));
        manager.setThreshold(1);
    }

    // === attestation

    function setup_endpoints() internal returns (DummyEndpoint, DummyEndpoint) {
        DummyEndpoint e1 = new DummyEndpoint(address(manager));
        DummyEndpoint e2 = new DummyEndpoint(address(manager));
        manager.setEndpoint(address(e1));
        manager.setEndpoint(address(e2));
        return (e1, e2);
    }

    function test_onlyEnabledEndpointsCanAttest() public {
        (DummyEndpoint e1,) = setup_endpoints();
        manager.removeEndpoint(address(e1));

        EndpointStructs.ManagerMessage memory m = EndpointStructs.ManagerMessage(
            0, 0, 1, abi.encode(EndpointStructs.EndpointMessage("hello", "world", "payload"))
        );
        bytes memory message = EndpointStructs.encodeManagerMessage(m);

        bytes4 selector = bytes4(keccak256("CallerNotEndpoint(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(e1)));
        e1.receiveMessage(message);
    }

    function test_attest() public {
        (DummyEndpoint e1,) = setup_endpoints();
        manager.setThreshold(2);

        EndpointStructs.ManagerMessage memory m = EndpointStructs.ManagerMessage(
            0, 0, 1, abi.encode(EndpointStructs.EndpointMessage("hello", "world", "payload"))
        );

        bytes memory message = EndpointStructs.encodeManagerMessage(m);

        e1.receiveMessage(message);

        bytes32 hash = EndpointStructs.managerMessageDigest(m);
        assertEq(manager.messageAttestations(hash), 1);
    }

    function test_attestTwice() public {
        (DummyEndpoint e1,) = setup_endpoints();
        manager.setThreshold(2);

        EndpointStructs.ManagerMessage memory m = EndpointStructs.ManagerMessage(
            0, 0, 1, abi.encode(EndpointStructs.EndpointMessage("hello", "world", "payload"))
        );

        bytes memory message = EndpointStructs.encodeManagerMessage(m);

        e1.receiveMessage(message);
        e1.receiveMessage(message);

        bytes32 hash = EndpointStructs.managerMessageDigest(m);
        // can't double vote
        assertEq(manager.messageAttestations(hash), 1);
    }

    function test_attestDisabled() public {
        (DummyEndpoint e1,) = setup_endpoints();
        manager.setThreshold(2);

        EndpointStructs.ManagerMessage memory m = EndpointStructs.ManagerMessage(
            0, 0, 1, abi.encode(EndpointStructs.EndpointMessage("hello", "world", "payload"))
        );

        bytes memory message = EndpointStructs.encodeManagerMessage(m);

        e1.receiveMessage(message);
        manager.setThreshold(1);
        manager.removeEndpoint(address(e1));

        bytes32 hash = EndpointStructs.managerMessageDigest(m);
        // a disabled endpoint's vote no longer counts
        assertEq(manager.messageAttestations(hash), 0);

        manager.setEndpoint(address(e1));
        // it counts again when reenabled
        assertEq(manager.messageAttestations(hash), 1);
    }

    function test_transfer_sequences() public {
        address user_A = address(0x123);
        address user_B = address(0x456);

        manager.setOutboundLimit(type(uint256).max);

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);

        vm.startPrank(user_A);

        token.approve(address(manager), 3 * 10 ** decimals);

        uint64 s1 = manager.transfer(1 * 10 ** decimals, chainId, toWormholeFormat(user_B), false);
        uint64 s2 = manager.transfer(1 * 10 ** decimals, chainId, toWormholeFormat(user_B), false);
        uint64 s3 = manager.transfer(1 * 10 ** decimals, chainId, toWormholeFormat(user_B), false);

        assertEq(s1, 0);
        assertEq(s2, 1);
        assertEq(s3, 2);
    }

    function test_attestationQuorum() public {
        address user_A = address(0x123);
        address user_B = address(0x456);

        (DummyEndpoint e1, DummyEndpoint e2) = setup_endpoints();

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);
        manager.setOutboundLimit(type(uint256).max);
        manager.setInboundLimit(type(uint256).max, 0);

        vm.startPrank(user_A);

        token.approve(address(manager), 3 * 10 ** decimals);
        // we add 500 dust to check that the rounding code works.
        manager.transfer(3 * 10 ** decimals + 500, chainId, toWormholeFormat(user_B), false);

        assertEq(token.balanceOf(address(user_A)), 2 * 10 ** decimals);
        assertEq(token.balanceOf(address(manager)), 3 * 10 ** decimals);

        EndpointStructs.ManagerMessage memory m = EndpointStructs.ManagerMessage(
            0,
            0,
            1,
            EndpointStructs.encodeNativeTokenTransfer(
                EndpointStructs.NativeTokenTransfer({
                    amount: 50,
                    to: abi.encodePacked(user_B),
                    toChain: chainId
                })
            )
        );

        bytes memory message = EndpointStructs.encodeManagerMessage(m);

        e1.receiveMessage(message);

        // no quorum yet
        assertEq(token.balanceOf(address(user_B)), 0);

        e2.receiveMessage(message);

        assertEq(token.balanceOf(address(user_B)), 50 * 10 ** (decimals - 8));

        // replay protection
        bytes4 selector = bytes4(keccak256("MessageAlreadyExecuted(bytes32)"));
        vm.expectRevert(abi.encodeWithSelector(selector, EndpointStructs.managerMessageDigest(m)));
        e2.receiveMessage(message);
    }

    // TODO:
    // currently there is no way to test the threshold logic and the duplicate
    // protection logic without setting up the business logic as well.
    //
    // we should separate the business logic out from the endpoint handling.
    // that way the functionality could be tested separately (and the contracts
    // would also be more reusable)

    // === message encoding/decoding

    // TODO: add some negative tests for unknown message types etc

    function test_SerdeRoundtrip_ManagerMessage(EndpointStructs.ManagerMessage memory m) public {
        bytes memory message = EndpointStructs.encodeManagerMessage(m);

        EndpointStructs.ManagerMessage memory parsed = EndpointStructs.parseManagerMessage(message);

        assertEq(m.chainId, parsed.chainId);
        assertEq(m.sequence, parsed.sequence);
        assertEq(m.msgType, parsed.msgType);
        assertEq(m.payload, parsed.payload);
    }

    function test_SerdeJunk_ManagerMessage(EndpointStructs.ManagerMessage memory m) public {
        bytes memory message = EndpointStructs.encodeManagerMessage(m);

        bytes memory junk = "junk";

        bytes4 selector = bytes4(keccak256("LengthMismatch(uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, message.length + junk.length, message.length)
        );
        EndpointStructs.parseManagerMessage(abi.encodePacked(message, junk));
    }

    function test_SerdeRoundtrip_NativeTokenTransfer(EndpointStructs.NativeTokenTransfer memory m)
        public
    {
        bytes memory message = EndpointStructs.encodeNativeTokenTransfer(m);

        EndpointStructs.NativeTokenTransfer memory parsed =
            EndpointStructs.parseNativeTokenTransfer(message);

        assertEq(m.amount, parsed.amount);
        assertEq(m.to, parsed.to);
        assertEq(m.toChain, parsed.toChain);
    }

    function test_SerdeJunk_NativeTokenTransfer(EndpointStructs.NativeTokenTransfer memory m)
        public
    {
        bytes memory message = EndpointStructs.encodeNativeTokenTransfer(m);

        bytes memory junk = "junk";

        bytes4 selector = bytes4(keccak256("LengthMismatch(uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, message.length + junk.length, message.length)
        );
        EndpointStructs.parseNativeTokenTransfer(abi.encodePacked(message, junk));
    }

    function test_bytesToAddress_roundtrip(address a) public {
        bytes memory b = abi.encodePacked(a);
        assertEq(manager.bytesToAddress(b), a);
    }

    function test_bytesToAddress_junk(address a) public {
        bytes memory b = abi.encodePacked(a, "junk");

        bytes4 selector = bytes4(keccak256("LengthMismatch(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 24, 20));
        manager.bytesToAddress(b);
    }

    // === storage

    function test_noAutomaticSlot() public {
        assertEq(ManagerContract(address(manager)).lastSlot(), 0x0);
    }

    // === token transfer rate limiting

    function test_outboundRateLimit_setLimitSimple() public {
        uint256 limit = 1 * 10 ** 6;
        manager.setOutboundLimit(limit);

        IManager.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

        assertEq(outboundLimitParams.limit, limit);
        assertEq(outboundLimitParams.currentCapacity, limit);
        assertEq(outboundLimitParams.ratePerSecond, limit / manager._rateLimitDuration());
        assertEq(outboundLimitParams.lastTxTimestamp, 1);
    }

    function test_outboundRateLimit_setHigherLimit() public {
        // transfer 3 tokens
        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);
        uint256 outboundLimit = 4 * 10 ** decimals;
        manager.setOutboundLimit(outboundLimit);

        vm.startPrank(user_A);

        uint256 transferAmount = 3 * 10 ** decimals;
        token.approve(address(manager), transferAmount);
        manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false);

        vm.stopPrank();

        // update the outbound limit to 5 tokens
        vm.startPrank(address(this));

        uint256 higherLimit = 5 * 10 ** decimals;
        manager.setOutboundLimit(higherLimit);

        IManager.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

        assertEq(outboundLimitParams.limit, higherLimit);
        assertEq(outboundLimitParams.lastTxTimestamp, 1);
        assertEq(outboundLimitParams.currentCapacity, 2 * 10 ** decimals);
        assertEq(outboundLimitParams.ratePerSecond, higherLimit / manager._rateLimitDuration());
    }

    function test_outboundRateLimit_setLowerLimit() public {
        // transfer 3 tokens
        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);
        uint256 outboundLimit = 4 * 10 ** decimals;
        manager.setOutboundLimit(outboundLimit);

        vm.startPrank(user_A);

        uint256 transferAmount = 3 * 10 ** decimals;
        token.approve(address(manager), transferAmount);
        manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false);

        vm.stopPrank();

        // update the outbound limit to 5 tokens
        vm.startPrank(address(this));

        uint256 lowerLimit = 2 * 10 ** decimals;
        manager.setOutboundLimit(lowerLimit);

        IManager.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

        assertEq(outboundLimitParams.limit, lowerLimit);
        assertEq(outboundLimitParams.lastTxTimestamp, 1);
        assertEq(outboundLimitParams.currentCapacity, 0);
        assertEq(outboundLimitParams.ratePerSecond, lowerLimit / manager._rateLimitDuration());
    }

    function test_outboundRateLimit_setHigherLimit_duration() public {
        // transfer 3 tokens
        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);
        uint256 outboundLimit = 4 * 10 ** decimals;
        uint256 oldRps = outboundLimit / manager._rateLimitDuration();
        manager.setOutboundLimit(outboundLimit);

        vm.startPrank(user_A);

        uint256 transferAmount = 3 * 10 ** decimals;
        token.approve(address(manager), transferAmount);
        manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false);

        vm.stopPrank();

        // change block timestamp to be 6 hours later
        uint256 sixHoursLater = 21601;
        vm.warp(sixHoursLater);

        // update the outbound limit to 5 tokens
        vm.startPrank(address(this));

        uint256 higherLimit = 5 * 10 ** decimals;
        manager.setOutboundLimit(higherLimit);

        IManager.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

        assertEq(outboundLimitParams.limit, higherLimit);
        assertEq(outboundLimitParams.lastTxTimestamp, sixHoursLater);
        // capacity should be:
        // difference in limits + remaining capacity after t1 + the amount that's refreshed (based on the old rps)
        assertEq(
            outboundLimitParams.currentCapacity,
            (1 * 10 ** decimals) + (1 * 10 ** decimals) + oldRps * (sixHoursLater - 1)
        );
        assertEq(outboundLimitParams.ratePerSecond, higherLimit / manager._rateLimitDuration());
    }

    function test_outboundRateLimit_setLowerLimit_durationCaseOne() public {
        // transfer 3 tokens
        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);
        uint256 outboundLimit = 5 * 10 ** decimals;
        manager.setOutboundLimit(outboundLimit);

        vm.startPrank(user_A);

        uint256 transferAmount = 4 * 10 ** decimals;
        token.approve(address(manager), transferAmount);
        manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false);

        vm.stopPrank();

        // change block timestamp to be 3 hours later
        uint256 sixHoursLater = 10801;
        vm.warp(sixHoursLater);

        // update the outbound limit to 5 tokens
        vm.startPrank(address(this));

        uint256 lowerLimit = 3 * 10 ** decimals;
        manager.setOutboundLimit(lowerLimit);

        IManager.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

        assertEq(outboundLimitParams.limit, lowerLimit);
        assertEq(outboundLimitParams.lastTxTimestamp, sixHoursLater);
        // capacity should be: 0
        assertEq(outboundLimitParams.currentCapacity, 0);
        assertEq(outboundLimitParams.ratePerSecond, lowerLimit / manager._rateLimitDuration());
    }

    function test_outboundRateLimit_setLowerLimit_durationCaseTwo() public {
        // transfer 3 tokens
        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);
        uint256 outboundLimit = 5 * 10 ** decimals;
        uint256 oldRps = outboundLimit / manager._rateLimitDuration();
        manager.setOutboundLimit(outboundLimit);

        vm.startPrank(user_A);

        uint256 transferAmount = 2 * 10 ** decimals;
        token.approve(address(manager), transferAmount);
        manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false);

        vm.stopPrank();

        // change block timestamp to be 6 hours later
        uint256 sixHoursLater = 21601;
        vm.warp(sixHoursLater);

        // update the outbound limit to 5 tokens
        vm.startPrank(address(this));

        uint256 lowerLimit = 4 * 10 ** decimals;
        manager.setOutboundLimit(lowerLimit);

        IManager.RateLimitParams memory outboundLimitParams = manager.getOutboundLimitParams();

        assertEq(outboundLimitParams.limit, lowerLimit);
        assertEq(outboundLimitParams.lastTxTimestamp, sixHoursLater);
        // capacity should be:
        // remaining capacity after t1 - difference in limits + the amount that's refreshed (based on the old rps)
        assertEq(
            outboundLimitParams.currentCapacity,
            (3 * 10 ** decimals) - (1 * 10 ** decimals) + oldRps * (sixHoursLater - 1)
        );
        assertEq(outboundLimitParams.ratePerSecond, lowerLimit / manager._rateLimitDuration());
    }

    function test_outboundRateLimit_singleHit() public {
        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);
        uint256 outboundLimit = 1 * 10 ** decimals;
        manager.setOutboundLimit(outboundLimit);

        vm.startPrank(user_A);

        uint256 transferAmount = 3 * 10 ** decimals;
        token.approve(address(manager), transferAmount);

        bytes4 selector = bytes4(keccak256("NotEnoughOutboundCapacity(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, outboundLimit, transferAmount));
        manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false);
    }

    function test_outboundRateLimit_multiHit() public {
        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);
        uint256 outboundLimit = 4 * 10 ** decimals;
        manager.setOutboundLimit(outboundLimit);

        vm.startPrank(user_A);

        uint256 transferAmount = 3 * 10 ** decimals;
        token.approve(address(manager), transferAmount);
        manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), false);

        // assert that first transfer went through
        assertEq(token.balanceOf(address(user_A)), 2 * 10 ** decimals);
        assertEq(token.balanceOf(address(manager)), transferAmount);

        // assert currentCapacity is updated
        uint256 newCapacity = outboundLimit - transferAmount;
        assertEq(manager.getCurrentOutboundCapacity(), newCapacity);

        uint256 badTransferAmount = 2 * 10 ** decimals;
        token.approve(address(manager), badTransferAmount);

        bytes4 selector = bytes4(keccak256("NotEnoughOutboundCapacity(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, newCapacity, badTransferAmount));
        manager.transfer(badTransferAmount, chainId, toWormholeFormat(user_B), false);
    }

    // make a transfer with shouldQueue == true
    // check that it hits rate limit and gets inserted into the queue
    // test that it remains in queue after < _rateLimitDuration
    // test that it exits queue after >= _rateLimitDuration
    // test that it's removed from queue and can't be replayed
    function test_outboundRateLimit_queue() public {
        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);
        uint256 outboundLimit = 4 * 10 ** decimals;
        manager.setOutboundLimit(outboundLimit);

        vm.startPrank(user_A);

        uint256 transferAmount = 5 * 10 ** decimals;
        token.approve(address(manager), transferAmount);

        // transfer with shouldQueue == true
        uint64 qSeq = manager.transfer(transferAmount, chainId, toWormholeFormat(user_B), true);

        // assert that the transfer got queued up
        assertEq(qSeq, 0);
        IManager.OutboundQueuedTransfer memory qt = manager.getOutboundQueuedTransfer(0);
        assertEq(qt.amount, transferAmount);
        assertEq(qt.recipientChain, chainId);
        assertEq(qt.recipient, toWormholeFormat(user_B));
        assertEq(qt.txTimestamp, 1);

        // assert that the contract also locked funds from the user
        assertEq(token.balanceOf(address(user_A)), 0);
        assertEq(token.balanceOf(address(manager)), transferAmount);

        // change block time to (duration - 1) seconds later
        vm.warp(manager._rateLimitDuration());

        // assert that transfer still can't be completed
        bytes4 stillQueuedSelector = bytes4(keccak256("QueuedTransferStillQueued(uint64,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(stillQueuedSelector, 0, 1));
        manager.completeOutboundQueuedTransfer(0);

        // now complete transfer
        vm.warp(manager._rateLimitDuration() + 1);
        uint64 seq = manager.completeOutboundQueuedTransfer(0);
        assertEq(seq, 0);

        // now ensure transfer was removed from queue
        bytes4 notFoundSelector = bytes4(keccak256("QueuedTransferNotFound(uint64)"));
        vm.expectRevert(abi.encodeWithSelector(notFoundSelector, 0));
        manager.completeOutboundQueuedTransfer(0);
    }

    function test_inboundRateLimit() public {
        address user_A = address(0x123);
        address user_B = address(0x456);

        (DummyEndpoint e1, DummyEndpoint e2) = setup_endpoints();

        DummyToken token = DummyToken(manager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);
        manager.setOutboundLimit(type(uint256).max);
        manager.setInboundLimit(5, 0);

        vm.startPrank(user_A);

        token.approve(address(manager), 3 * 10 ** decimals);
        // we add 500 dust to check that the rounding code works.
        manager.transfer(3 * 10 ** decimals + 500, chainId, toWormholeFormat(user_B), false);

        assertEq(token.balanceOf(address(user_A)), 2 * 10 ** decimals);
        assertEq(token.balanceOf(address(manager)), 3 * 10 ** decimals);

        EndpointStructs.ManagerMessage memory m = EndpointStructs.ManagerMessage(
            0,
            0,
            1,
            EndpointStructs.encodeNativeTokenTransfer(
                EndpointStructs.NativeTokenTransfer({
                    amount: 50,
                    to: abi.encodePacked(user_B),
                    toChain: chainId
                })
            )
        );

        bytes memory message = EndpointStructs.encodeManagerMessage(m);

        e1.receiveMessage(message);

        // no quorum yet
        assertEq(token.balanceOf(address(user_B)), 0);

        vm.expectEmit(address(manager));
        emit InboundTransferQueued(0, 0);
        e2.receiveMessage(message);

        // now we have quorum but it'll hit limit
        assertEq(manager.nextInboundQueueSequence(), 1);
        IManager.InboundQueuedTransfer memory qt = manager.getInboundQueuedTransfer(0);
        assertEq(qt.amount, 50 * 10 ** (decimals - 8));
        assertEq(qt.txTimestamp, 1);
        assertEq(qt.recipient, user_B);

        // assert that the user doesn't have funds yet
        assertEq(token.balanceOf(address(user_B)), 0);

        // change block time to (duration - 1) seconds later
        vm.warp(manager._rateLimitDuration());

        // assert that transfer still can't be completed
        bytes4 stillQueuedSelector = bytes4(keccak256("QueuedTransferStillQueued(uint64,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(stillQueuedSelector, 0, 1));
        manager.completeInboundQueuedTransfer(0);

        // now complete transfer
        vm.warp(manager._rateLimitDuration() + 1);
        manager.completeInboundQueuedTransfer(0);

        // assert transfer no longer in queue
        bytes4 notQueuedSelector = bytes4(keccak256("QueuedTransferNotFound(uint64)"));
        vm.expectRevert(abi.encodeWithSelector(notQueuedSelector, 0));
        manager.completeInboundQueuedTransfer(0);

        // assert user now has funds
        assertEq(token.balanceOf(address(user_B)), 50 * 10 ** (decimals - 8));

        // replay protection
        bytes4 selector = bytes4(keccak256("MessageAlreadyExecuted(bytes32)"));
        vm.expectRevert(abi.encodeWithSelector(selector, EndpointStructs.managerMessageDigest(m)));
        e2.receiveMessage(message);
    }
}

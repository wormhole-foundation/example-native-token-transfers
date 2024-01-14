// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "forge-std/Test.sol";

import "../src/EndpointManagerStandalone.sol";
import "../src/EndpointStandalone.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// @dev A non-abstract EndpointManager contract
contract EndpointManagerContract is EndpointManagerStandalone {
    constructor(
        address token,
        Mode mode,
        uint16 chainId
    ) EndpointManagerStandalone(token, mode, chainId) {}
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
contract TestEndpointManager is Test {
    EndpointManagerStandalone endpointManager;
    uint16 constant chainId = 7;

    function setUp() public {
        DummyToken t = new DummyToken();
        endpointManager =
            new EndpointManagerContract(address(t), EndpointManager.Mode.LOCKING, chainId);
        endpointManager.initialize();
        // deploy sample token contract
        // deploy wormhole contract
        // wormhole = deployWormholeForTest();
        // deploy endpoint contracts
        // instantiate endpoint manager contract
        // endpointManager = new EndpointManagerContract();
    }

    // === pure unit tests

    function test_countSetBits() public {
        assertEq(endpointManager.countSetBits(5), 2);
        assertEq(endpointManager.countSetBits(0), 0);
        assertEq(endpointManager.countSetBits(15), 4);
        assertEq(endpointManager.countSetBits(16), 1);
        assertEq(endpointManager.countSetBits(65535), 16);
    }

    // === ownership

    function test_owner() public {
        // TODO: implement separate governance contract
        assertEq(endpointManager.owner(), address(this));
    }

    function test_transferOwnership() public {
        address newOwner = address(0x123);
        endpointManager.transferOwnership(newOwner);
        assertEq(endpointManager.owner(), newOwner);
    }

    function test_onlyOwnerCanTransferOwnership() public {
        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, notOwner));
        endpointManager.transferOwnership(address(0x456));
    }

    // === endpoint registration

    function test_registerEndpoint() public {
        DummyEndpoint e = new DummyEndpoint(address(endpointManager));
        endpointManager.setEndpoint(address(e));
    }

    function test_onlyOwnerCanModifyEndpoints() public {
        DummyEndpoint e = new DummyEndpoint(address(endpointManager));
        endpointManager.setEndpoint(address(e));

        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, notOwner));
        endpointManager.setEndpoint(address(e));

        vm.expectRevert(abi.encodeWithSelector(selector, notOwner));
        endpointManager.removeEndpoint(address(e));
    }

    function test_cantEnableEndpointTwice() public {
        DummyEndpoint e = new DummyEndpoint(address(endpointManager));
        endpointManager.setEndpoint(address(e));

        bytes4 selector = bytes4(keccak256("EndpointAlreadyEnabled(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(e)));
        endpointManager.setEndpoint(address(e));
    }

    function test_disableReenableEndpoint() public {
        DummyEndpoint e = new DummyEndpoint(address(endpointManager));
        endpointManager.setEndpoint(address(e));
        endpointManager.removeEndpoint(address(e));
        endpointManager.setEndpoint(address(e));
    }

    function test_multipleEndpoints() public {
        DummyEndpoint e1 = new DummyEndpoint(address(endpointManager));
        DummyEndpoint e2 = new DummyEndpoint(address(endpointManager));

        endpointManager.setEndpoint(address(e1));
        endpointManager.setEndpoint(address(e2));
    }

    function test_endpointIncompatibleManager() public {
        // TODO: this is accepted currently. should we include a check to ensure
        // only endpoints whose manager is us can be registered? (this would be
        // a convenience check, not a security one)
        DummyEndpoint e = new DummyEndpoint(address(0xBEEF));
        endpointManager.setEndpoint(address(e));
    }

    function test_notEndpoint() public {
        // TODO: this is accepted currently. should we include a check to ensure
        // only endpoints can be registered? (this would be a convenience check, not a security one)
        endpointManager.setEndpoint(address(0x123));
    }

    // == threshold

    function test_cantSetThresholdTooHigh() public {
        // no endpoints set, so can't set threshold to 1
        bytes4 selector = bytes4(keccak256("ThresholdTooHigh(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 1, 0));
        endpointManager.setThreshold(1);
    }

    function test_canSetThreshold() public {
        DummyEndpoint e1 = new DummyEndpoint(address(endpointManager));
        DummyEndpoint e2 = new DummyEndpoint(address(endpointManager));
        endpointManager.setEndpoint(address(e1));
        endpointManager.setEndpoint(address(e2));

        endpointManager.setThreshold(1);
        endpointManager.setThreshold(2);
        endpointManager.setThreshold(1);
    }

    function test_cantSetThresholdToZero() public {
        DummyEndpoint e = new DummyEndpoint(address(endpointManager));
        endpointManager.setEndpoint(address(e));

        bytes4 selector = bytes4(keccak256("ZeroThreshold()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        endpointManager.setThreshold(0);
    }

    function test_onlyOwnerCanSetThreshold() public {
        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, notOwner));
        endpointManager.setThreshold(1);
    }

    // === attestation

    function setup_endpoints() internal returns (DummyEndpoint, DummyEndpoint) {
        DummyEndpoint e1 = new DummyEndpoint(address(endpointManager));
        DummyEndpoint e2 = new DummyEndpoint(address(endpointManager));
        endpointManager.setEndpoint(address(e1));
        endpointManager.setEndpoint(address(e2));
        return (e1, e2);
    }

    function test_onlyEnabledEndpointsCanAttest() public {
        (DummyEndpoint e1,) = setup_endpoints();
        endpointManager.removeEndpoint(address(e1));

        bytes4 selector = bytes4(keccak256("CallerNotEndpoint(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(e1)));
        e1.receiveMessage("hello");
    }

    function test_attest() public {
        (DummyEndpoint e1,) = setup_endpoints();
        endpointManager.setThreshold(2);

        EndpointManagerMessage memory m = EndpointManagerMessage(
            0, 0, 1, abi.encode(EndpointMessage("hello", "world", "payload"))
        );

        bytes memory message = endpointManager.encodeEndpointManagerMessage(m);

        e1.receiveMessage(message);

        bytes32 hash = endpointManager.computeManagerMessageHash(message);
        assertEq(endpointManager.messageAttestations(hash), 1);
    }

    function test_attestTwice() public {
        (DummyEndpoint e1,) = setup_endpoints();
        endpointManager.setThreshold(2);

        EndpointManagerMessage memory m = EndpointManagerMessage(
            0, 0, 1, abi.encode(EndpointMessage("hello", "world", "payload"))
        );

        bytes memory message = endpointManager.encodeEndpointManagerMessage(m);

        e1.receiveMessage(message);
        e1.receiveMessage(message);

        bytes32 hash = endpointManager.computeManagerMessageHash(message);
        // can't double vote
        assertEq(endpointManager.messageAttestations(hash), 1);
    }

    function test_attestDisabled() public {
        (DummyEndpoint e1,) = setup_endpoints();
        endpointManager.setThreshold(2);

        EndpointManagerMessage memory m = EndpointManagerMessage(
            0, 0, 1, abi.encode(EndpointMessage("hello", "world", "payload"))
        );

        bytes memory message = endpointManager.encodeEndpointManagerMessage(m);

        e1.receiveMessage(message);
        endpointManager.setThreshold(1);
        endpointManager.removeEndpoint(address(e1));

        bytes32 hash = endpointManager.computeManagerMessageHash(message);
        // a disabled endpoint's vote no longer counts
        assertEq(endpointManager.messageAttestations(hash), 0);

        endpointManager.setEndpoint(address(e1));
        // it counts again when reenabled
        assertEq(endpointManager.messageAttestations(hash), 1);
    }

    function test_attestationQuorum() public {
        address user_A = address(0x123);
        address user_B = address(0x456);

        (DummyEndpoint e1, DummyEndpoint e2) = setup_endpoints();

        DummyToken token = DummyToken(endpointManager.token());

        uint256 decimals = token.decimals();

        token.mintDummy(address(user_A), 5 * 10 ** decimals);

        vm.startPrank(user_A);

        token.approve(address(endpointManager), 3 * 10 ** decimals);
        // we add 500 dust to check that the rounding code works.
        endpointManager.transfer(3 * 10 ** decimals + 500, chainId, toWormholeFormat(user_B));

        assertEq(token.balanceOf(address(user_A)), 2 * 10 ** decimals);
        assertEq(token.balanceOf(address(endpointManager)), 3 * 10 ** decimals);

        EndpointManagerMessage memory m = EndpointManagerMessage(
            0,
            0,
            1,
            endpointManager.encodeNativeTokenTransfer(
                NativeTokenTransfer({
                    amount: 50,
                    tokenAddress: "",
                    to: toWormholeFormat(user_B),
                    toChain: chainId
                })
            )
        );

        bytes memory message = endpointManager.encodeEndpointManagerMessage(m);

        e1.receiveMessage(message);

        // no quorum yet
        assertEq(token.balanceOf(address(user_B)), 0);

        e2.receiveMessage(message);

        assertEq(token.balanceOf(address(user_B)), 50 * 10 ** (decimals - 8));
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

    function test_SerdeRoundtrip_EndpointManagerMessage(EndpointManagerMessage memory m) public {
        bytes memory message = endpointManager.encodeEndpointManagerMessage(m);

        EndpointManagerMessage memory parsed = endpointManager.parseEndpointManagerMessage(message);

        assertEq(m.chainId, parsed.chainId);
        assertEq(m.sequence, parsed.sequence);
        assertEq(m.msgType, parsed.msgType);
        assertEq(m.payload, parsed.payload);
    }

    function test_SerdeJunk_EndpointManagerMessage(EndpointManagerMessage memory m) public view {
        bytes memory message = endpointManager.encodeEndpointManagerMessage(m);

        bytes memory junk = "junk";

        // TODO: this should revert. we should add a length prefix to the payload
        endpointManager.parseEndpointManagerMessage(abi.encodePacked(message, junk));
    }

    function test_SerdeRoundtrip_NativeTokenTransfer(NativeTokenTransfer memory m) public {
        bytes memory message = endpointManager.encodeNativeTokenTransfer(m);

        NativeTokenTransfer memory parsed = endpointManager.parseNativeTokenTransfer(message);

        assertEq(m.amount, parsed.amount);
        assertEq(m.tokenAddress, parsed.tokenAddress);
        assertEq(m.to, parsed.to);
        assertEq(m.toChain, parsed.toChain);
    }

    function test_SerdeJunk_NativeTokenTransfer(NativeTokenTransfer memory m) public {
        bytes memory message = endpointManager.encodeNativeTokenTransfer(m);

        bytes memory junk = "junk";

        bytes4 selector = bytes4(keccak256("LengthMismatch(uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, message.length + junk.length, message.length)
        );
        endpointManager.parseNativeTokenTransfer(abi.encodePacked(message, junk));
    }
}

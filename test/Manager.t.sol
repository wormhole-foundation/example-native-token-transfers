// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";

import "../src/ManagerStandalone.sol";
import "../src/EndpointAndManager.sol";
import "../src/EndpointStandalone.sol";
import "../src/interfaces/IManager.sol";
import "../src/interfaces/IRateLimiter.sol";
import "../src/interfaces/IManagerEvents.sol";
import "../src/interfaces/IRateLimiterEvents.sol";
import {Utils} from "./libraries/Utils.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "wormhole-solidity-sdk/Utils.sol";
import "./libraries/EndpointHelpers.sol";
import "./libraries/ManagerHelpers.sol";
import "./interfaces/IEndpointReceiver.sol";
import "./mocks/DummyEndpoint.sol";
import "./mocks/DummyToken.sol";

// @dev A non-abstract Manager contract
contract ManagerContract is ManagerStandalone {
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration
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

contract EndpointAndManagerContract is EndpointAndManager, IEndpointReceiver {
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration
    ) EndpointAndManager(token, mode, chainId, rateLimitDuration) {}

    function _quoteDeliveryPrice(
        uint16, /* recipientChain */
        EndpointStructs.EndpointInstruction memory /* endpointInstruction */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        EndpointStructs.EndpointInstruction memory instruction,
        bytes memory payload
    ) internal pure override {
        // do nothing
    }

    function receiveMessage(bytes memory encodedMessage) external {
        EndpointStructs.EndpointMessage memory parsedEndpointMessage;
        EndpointStructs.ManagerMessage memory parsedManagerMessage;
        (parsedEndpointMessage, parsedManagerMessage) = EndpointStructs
            .parseEndpointAndManagerMessage(
            EndpointHelpersLib.TEST_ENDPOINT_PAYLOAD_PREFIX, encodedMessage
        );
        _deliverToManager(
            EndpointHelpersLib.SENDING_CHAIN_ID,
            parsedEndpointMessage.sourceManagerAddress,
            parsedManagerMessage
        );
    }
}

// TODO: set this up so the common functionality tests can be run against both
// the standalone and the integrated version of the endpoint manager
contract TestManager is Test, IManagerEvents, IRateLimiterEvents {
    ManagerStandalone manager;

    using NormalizedAmountLib for uint256;
    using NormalizedAmountLib for NormalizedAmount;

    // 0x99'E''T''T'
    uint16 constant chainId = 7;
    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;

    function setUp() public {
        string memory url = "https://ethereum-goerli.publicnode.com";
        IWormhole wormhole = IWormhole(0x706abc4E45D419950511e474C7B9Ed348A4a716c);
        vm.createSelectFork(url);
        initialBlockTimestamp = vm.getBlockTimestamp();

        guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);

        DummyToken t = new DummyToken();
        ManagerStandalone implementation =
            new ManagerStandalone(address(t), Manager.Mode.LOCKING, chainId, 1 days);

        manager = ManagerStandalone(address(new ERC1967Proxy(address(implementation), "")));
        manager.initialize();

        // deploy sample token contract
        // deploy wormhole contract
        // wormhole = deployWormholeForTest();
        // deploy endpoint contracts
        // instantiate endpoint manager contract
        // manager = new ManagerContract();
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

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", notOwner));
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

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", notOwner));
        manager.setEndpoint(address(e));

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", notOwner));
        manager.removeEndpoint(address(e));
    }

    function test_cantEnableEndpointTwice() public {
        DummyEndpoint e = new DummyEndpoint(address(manager));
        manager.setEndpoint(address(e));

        vm.expectRevert(abi.encodeWithSignature("EndpointAlreadyEnabled(address)", address(e)));
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
        vm.expectRevert(abi.encodeWithSignature("ThresholdTooHigh(uint256,uint256)", 1, 0));
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

        vm.expectRevert(abi.encodeWithSignature("ZeroThreshold()"));
        manager.setThreshold(0);
    }

    function test_onlyOwnerCanSetThreshold() public {
        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", notOwner));
        manager.setThreshold(1);
    }

    // === attestation

    function test_onlyEnabledEndpointsCanAttest() public {
        (DummyEndpoint e1,) = EndpointHelpersLib.setup_endpoints(manager);
        manager.removeEndpoint(address(e1));

        bytes memory endpointMessage;
        (, endpointMessage) = EndpointHelpersLib.buildEndpointMessageWithManagerPayload(
            0, bytes32(0), toWormholeFormat(address(manager)), abi.encode("payload")
        );

        vm.expectRevert(abi.encodeWithSignature("CallerNotEndpoint(address)", address(e1)));
        e1.receiveMessage(endpointMessage);
    }

    function test_onlySiblingManagerCanAttest() public {
        (DummyEndpoint e1,) = EndpointHelpersLib.setup_endpoints(manager);
        manager.setThreshold(2);

        bytes32 sibling = toWormholeFormat(address(manager));

        EndpointStructs.ManagerMessage memory managerMessage;
        bytes memory endpointMessage;
        (managerMessage, endpointMessage) = EndpointHelpersLib
            .buildEndpointMessageWithManagerPayload(0, bytes32(0), sibling, abi.encode("payload"));

        vm.expectRevert(
            abi.encodeWithSignature(
                "InvalidSibling(uint16,bytes32)", EndpointHelpersLib.SENDING_CHAIN_ID, sibling
            )
        );
        e1.receiveMessage(endpointMessage);
    }

    function test_attest() public {
        (DummyEndpoint e1,) = EndpointHelpersLib.setup_endpoints(manager);
        manager.setThreshold(2);

        // register manager sibling
        bytes32 sibling = toWormholeFormat(address(manager));
        manager.setSibling(EndpointHelpersLib.SENDING_CHAIN_ID, sibling);

        EndpointStructs.ManagerMessage memory managerMessage;
        bytes memory endpointMessage;
        (managerMessage, endpointMessage) = EndpointHelpersLib
            .buildEndpointMessageWithManagerPayload(0, bytes32(0), sibling, abi.encode("payload"));

        e1.receiveMessage(endpointMessage);

        bytes32 hash = EndpointStructs.managerMessageDigest(
            EndpointHelpersLib.SENDING_CHAIN_ID, managerMessage
        );
        assertEq(manager.messageAttestations(hash), 1);
    }

    function test_attestTwice() public {
        (DummyEndpoint e1,) = EndpointHelpersLib.setup_endpoints(manager);
        manager.setThreshold(2);

        // register manager sibling
        bytes32 sibling = toWormholeFormat(address(manager));
        manager.setSibling(EndpointHelpersLib.SENDING_CHAIN_ID, sibling);

        EndpointStructs.ManagerMessage memory managerMessage;
        bytes memory endpointMessage;
        (managerMessage, endpointMessage) = EndpointHelpersLib
            .buildEndpointMessageWithManagerPayload(0, bytes32(0), sibling, abi.encode("payload"));

        e1.receiveMessage(endpointMessage);
        e1.receiveMessage(endpointMessage);

        bytes32 hash = EndpointStructs.managerMessageDigest(
            EndpointHelpersLib.SENDING_CHAIN_ID, managerMessage
        );
        // can't double vote
        assertEq(manager.messageAttestations(hash), 1);
    }

    function test_attestDisabled() public {
        (DummyEndpoint e1,) = EndpointHelpersLib.setup_endpoints(manager);
        manager.setThreshold(2);

        IEndpointReceiver[] memory endpoints = new IEndpointReceiver[](1);
        endpoints[0] = e1;

        EndpointStructs.ManagerMessage memory m;
        (m,) = EndpointHelpersLib.attestEndpointsHelper(
            address(0x456),
            0,
            chainId,
            manager,
            NormalizedAmount(50, 8),
            NormalizedAmount(type(uint64).max, 8),
            endpoints
        );

        manager.removeEndpoint(address(e1));

        bytes32 hash = EndpointStructs.managerMessageDigest(EndpointHelpersLib.SENDING_CHAIN_ID, m);
        // a disabled endpoint's vote no longer counts
        assertEq(manager.messageAttestations(hash), 0);

        manager.setEndpoint(address(e1));
        // it counts again when reenabled
        assertEq(manager.messageAttestations(hash), 1);
    }

    function test_transfer_sequences() public {
        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(manager.token());

        uint8 decimals = token.decimals();

        manager.setOutboundLimit(NormalizedAmount(type(uint64).max, 8).denormalize(decimals));

        token.mintDummy(address(user_A), 5 * 10 ** decimals);

        vm.startPrank(user_A);

        token.approve(address(manager), 3 * 10 ** decimals);

        uint64 s1 = manager.transfer(
            1 * 10 ** decimals, chainId, toWormholeFormat(user_B), false, new bytes(1)
        );
        uint64 s2 = manager.transfer(
            1 * 10 ** decimals, chainId, toWormholeFormat(user_B), false, new bytes(1)
        );
        uint64 s3 = manager.transfer(
            1 * 10 ** decimals, chainId, toWormholeFormat(user_B), false, new bytes(1)
        );

        assertEq(s1, 0);
        assertEq(s2, 1);
        assertEq(s3, 2);
    }

    function test_attestationQuorum() public {
        address user_B = address(0x456);

        (DummyEndpoint e1, DummyEndpoint e2) = EndpointHelpersLib.setup_endpoints(manager);
        NormalizedAmount memory transferAmount = NormalizedAmount(50, 8);

        EndpointStructs.ManagerMessage memory m;
        bytes memory encodedEm;
        {
            IEndpointReceiver[] memory endpoints = new IEndpointReceiver[](2);
            endpoints[0] = e1;
            endpoints[1] = e2;

            EndpointStructs.EndpointMessage memory em;
            (m, em) = EndpointHelpersLib.attestEndpointsHelper(
                user_B,
                0,
                chainId,
                manager,
                transferAmount,
                NormalizedAmount(type(uint64).max, 8),
                endpoints
            );
            encodedEm = EndpointStructs.encodeEndpointMessage(
                EndpointHelpersLib.TEST_ENDPOINT_PAYLOAD_PREFIX, em
            );
        }

        {
            DummyToken token = DummyToken(manager.token());
            assertEq(token.balanceOf(address(user_B)), transferAmount.denormalize(token.decimals()));
        }

        // replay protection
        vm.recordLogs();
        e2.receiveMessage(encodedEm);

        {
            Vm.Log[] memory entries = vm.getRecordedLogs();
            assertEq(entries.length, 2);
            assertEq(entries[1].topics.length, 3);
            assertEq(entries[1].topics[0], keccak256("MessageAlreadyExecuted(bytes32,bytes32)"));
            assertEq(entries[1].topics[1], toWormholeFormat(address(manager)));
            assertEq(
                entries[1].topics[2],
                EndpointStructs.managerMessageDigest(EndpointHelpersLib.SENDING_CHAIN_ID, m)
            );
        }
    }

    // TODO:
    // currently there is no way to test the threshold logic and the duplicate
    // protection logic without setting up the business logic as well.
    //
    // we should separate the business logic out from the endpoint handling.
    // that way the functionality could be tested separately (and the contracts
    // would also be more reusable)

    // === storage

    function test_noAutomaticSlot() public {
        DummyToken t = new DummyToken();
        ManagerContract c = new ManagerContract(address(t), Manager.Mode.LOCKING, 1, 1 days);
        assertEq(c.lastSlot(), 0x0);
    }

    function test_constructor() public {
        DummyToken t = new DummyToken();

        vm.startStateDiffRecording();

        new ManagerStandalone(address(t), Manager.Mode.LOCKING, 1, 1 days);

        Utils.assertSafeUpgradeableConstructor(vm.stopAndReturnStateDiff());
    }

    // === token transfer logic

    function test_dustReverts() public {
        // transfer 3 tokens
        address from = address(0x123);
        address to = address(0x456);

        DummyToken token = DummyToken(manager.token());

        uint8 decimals = token.decimals();

        uint256 maxAmount = 5 * 10 ** decimals;
        token.mintDummy(from, maxAmount);
        manager.setOutboundLimit(NormalizedAmount(type(uint64).max, 8).denormalize(decimals));
        manager.setInboundLimit(
            NormalizedAmount(type(uint64).max, 8).denormalize(decimals),
            EndpointHelpersLib.SENDING_CHAIN_ID
        );

        vm.startPrank(from);

        uint256 transferAmount = 3 * 10 ** decimals;
        assertEq(
            transferAmount < maxAmount - 500, true, "Transferring more tokens than what exists"
        );

        uint256 dustAmount = 500;
        uint256 amountWithDust = transferAmount + dustAmount; // An amount with 19 digits, which will result in dust due to 18 decimals
        token.approve(address(manager), amountWithDust);

        vm.expectRevert(
            abi.encodeWithSignature(
                "TransferAmountHasDust(uint256,uint256)", amountWithDust, dustAmount
            )
        );
        manager.transfer(amountWithDust, chainId, toWormholeFormat(to), false, new bytes(1));

        vm.stopPrank();
    }

    // === upgradeability

    function test_upgrade() public {
        // The testing strategy here is as follows:
        // - Step 1: we deploy the standalone contract with two endpoints and
        //           receive a message through it
        // - Step 2: we upgrade it to the EndointAndManager contract and receive
        //           a message through it
        // - Step 3: we upgrade back to the standalone contract (with two
        //           endpoints) and receive a message through it
        //
        // This ensures that the storage slots don't get clobbered through the upgrades, and also that

        address user_B = address(0x456);

        DummyToken token = DummyToken(manager.token());

        // Step 1
        // (contract is deployed by setUp())
        NormalizedAmount memory transferAmount = NormalizedAmount(50, 8);

        (IEndpointReceiver e1, IEndpointReceiver e2) = EndpointHelpersLib.setup_endpoints(manager);

        IEndpointReceiver[] memory endpoints = new IEndpointReceiver[](2);
        endpoints[0] = e1;
        endpoints[1] = e2;

        EndpointStructs.ManagerMessage memory m;
        bytes memory encodedEm;
        {
            EndpointStructs.EndpointMessage memory em;
            (m, em) = EndpointHelpersLib.attestEndpointsHelper(
                user_B,
                0,
                chainId,
                manager,
                transferAmount,
                NormalizedAmount(type(uint64).max, 8),
                endpoints
            );
            encodedEm = EndpointStructs.encodeEndpointMessage(
                EndpointHelpersLib.TEST_ENDPOINT_PAYLOAD_PREFIX, em
            );
        }

        assertEq(token.balanceOf(address(user_B)), transferAmount.denormalize(token.decimals()));

        // Step 2

        EndpointAndManager endpointAndManagerImpl =
            new EndpointAndManagerContract(manager.token(), Manager.Mode.LOCKING, chainId, 1 days);
        manager.upgrade(address(endpointAndManagerImpl));

        endpoints = new IEndpointReceiver[](1);
        endpoints[0] = IEndpointReceiver(address(manager));

        // replay protection
        vm.recordLogs();
        IEndpointReceiver(address(manager)).receiveMessage(encodedEm);
        {
            Vm.Log[] memory entries = vm.getRecordedLogs();
            assertEq(entries.length, 1);
            assertEq(entries[0].topics.length, 3);
            assertEq(entries[0].topics[0], keccak256("MessageAlreadyExecuted(bytes32,bytes32)"));
            assertEq(entries[0].topics[1], toWormholeFormat(address(manager)));
            assertEq(
                entries[0].topics[2],
                EndpointStructs.managerMessageDigest(EndpointHelpersLib.SENDING_CHAIN_ID, m)
            );
        }

        EndpointHelpersLib.attestEndpointsHelper(
            user_B,
            1,
            chainId,
            manager,
            transferAmount,
            NormalizedAmount(type(uint64).max, 8),
            endpoints
        );

        assertEq(token.balanceOf(address(user_B)), transferAmount.denormalize(token.decimals()) * 2);

        // Step 3

        ManagerStandalone managerImpl =
            new ManagerStandalone(manager.token(), Manager.Mode.LOCKING, chainId, 1 days);
        manager.upgrade(address(managerImpl));

        endpoints = new IEndpointReceiver[](2);
        endpoints[0] = e1;
        // attest with e1 twice (just two make sure it's still not accepted)
        endpoints[1] = e1;

        EndpointHelpersLib.attestEndpointsHelper(
            user_B,
            2,
            chainId,
            manager,
            transferAmount,
            NormalizedAmount(type(uint64).max, 8),
            endpoints
        );

        // balance is the same as before
        assertEq(token.balanceOf(address(user_B)), transferAmount.denormalize(token.decimals()) * 2);

        endpoints = new IEndpointReceiver[](1);
        endpoints[0] = e2;

        EndpointHelpersLib.attestEndpointsHelper(
            user_B,
            2,
            chainId,
            manager,
            transferAmount,
            NormalizedAmount(type(uint64).max, 8),
            endpoints
        );

        assertEq(token.balanceOf(address(user_B)), transferAmount.denormalize(token.decimals()) * 3);
    }
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/interfaces/IManagerBase.sol";
import "./libraries/NttManagerHelpers.sol";
import "./mocks/MockNttManager.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "./mocks/DummyTransceiver.sol";
import "../src/mocks/DummyToken.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/NttManager/TransceiverRegistry.sol";

contract TestManagerBase is Test, IRateLimiterEvents {
    MockNttManagerContract nttManager;
    MockNttManagerContract nttManagerOther;
    MockNttManagerContract nttManagerZeroRateLimiter;

    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    // 0x99'E''T''T'
    uint16 constant chainId = 7;
    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;
    DummyTransceiver dummyTransceiver;

    function setUp() public {
        string memory url = "https://ethereum-sepolia-rpc.publicnode.com";
        IWormhole wormhole = IWormhole(0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78);
        vm.createSelectFork(url);
        initialBlockTimestamp = vm.getBlockTimestamp();

        guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);

        DummyToken t = new DummyToken();
        ManagerBase implementation = new MockNttManagerContract(
            address(t), IManagerBase.Mode.LOCKING, chainId, 1 days, false
        );
        nttManager = MockNttManagerContract(address(new ERC1967Proxy(address(implementation), "")));
        nttManager.initialize();

        dummyTransceiver = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(dummyTransceiver));
    }

    // ================== TEST TRANSCEIVER REGISTRATION FUNCTIONALITY ================ //

    function test_registerTransceiver() public {
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));
    }

    function test_onlyOwnerCanModifyTransceivers() public {
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));

        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner)
        );
        nttManager.setTransceiver(address(e));

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner)
        );
        nttManager.removeTransceiver(address(e));
    }

    function test_cantEnableTransceiverTwice() public {
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));

        vm.expectRevert(
            abi.encodeWithSelector(
                TransceiverRegistry.TransceiverAlreadyEnabled.selector, address(e)
            )
        );
        nttManager.setTransceiver(address(e));
    }

    function test_disableReenableTransceiver() public {
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));
        nttManager.removeTransceiver(address(e));
        nttManager.setTransceiver(address(e));
    }

    function test_multipleTransceivers() public {
        DummyTransceiver e1 = new DummyTransceiver(address(nttManager));
        DummyTransceiver e2 = new DummyTransceiver(address(nttManager));

        nttManager.setTransceiver(address(e1));
        nttManager.setTransceiver(address(e2));
    }

    function test_transceiverIncompatibleNttManager() public {
        // Transceiver instantiation reverts if the nttManager doesn't have the proper token method
        vm.expectRevert(bytes(""));
        new DummyTransceiver(address(0xBEEF));
    }

    function test_transceiverWrongNttManager() public {
        // TODO: this is accepted currently. should we include a check to ensure
        // only transceivers whose nttManager is us can be registered? (this would be
        // a convenience check, not a security one)
        DummyToken t = new DummyToken();
        NttManager altNttManager = new MockNttManagerContract(
            address(t), IManagerBase.Mode.LOCKING, chainId, 1 days, false
        );
        DummyTransceiver e = new DummyTransceiver(address(altNttManager));
        nttManager.setTransceiver(address(e));
    }

    function test_noEnabledTransceivers() public {
        nttManager.removeTransceiver(address(dummyTransceiver));

        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(nttManager.token());

        uint8 decimals = token.decimals();

        nttManager.setPeer(chainId, toWormholeFormat(address(0x1)), 9, type(uint64).max);
        nttManager.setOutboundLimit(packTrimmedAmount(type(uint64).max, 8).untrim(decimals));

        token.mintDummy(address(user_A), 5 * 10 ** decimals);

        vm.startPrank(user_A);

        token.approve(address(nttManager), 3 * 10 ** decimals);

        vm.expectRevert(abi.encodeWithSelector(IManagerBase.NoEnabledTransceivers.selector));
        nttManager.transfer(
            1 * 10 ** decimals,
            chainId,
            toWormholeFormat(user_B),
            toWormholeFormat(user_A),
            false,
            new bytes(1)
        );
    }

    function test_notTransceiver() public {
        // TODO: this is accepted currently. should we include a check to ensure
        // only transceivers can be registered? (this would be a convenience check, not a security one)
        nttManager.setTransceiver(address(0x123));
    }

    function test_maxOutTransceivers() public {
        // Let's register a transceiver and then disable it. We now have 2 registered managers
        // since we register 1 in the setup
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));
        nttManager.removeTransceiver(address(e));

        // We should be able to register 64 transceivers total
        for (uint256 i = 0; i < 62; ++i) {
            DummyTransceiver d = new DummyTransceiver(address(nttManager));
            nttManager.setTransceiver(address(d));
        }

        // Registering a new transceiver should fail as we've hit the cap
        DummyTransceiver c = new DummyTransceiver(address(nttManager));
        vm.expectRevert(TransceiverRegistry.TooManyTransceivers.selector);
        nttManager.setTransceiver(address(c));

        // We should be able to renable an already registered transceiver at the cap
        nttManager.setTransceiver(address(e));
    }
}

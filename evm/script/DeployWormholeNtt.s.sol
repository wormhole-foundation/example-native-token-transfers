// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import "../src/interfaces/INttManager.sol";

import {NttManager} from "../src/NttManager/NttManager.sol";
import {WormholeTransceiver} from "../src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployWormholeNtt is Script {
    struct DeploymentParams {
        address token;
        INttManager.Mode mode;
        uint16 wormholeChainId;
        uint64 rateLimitDuration;
        address wormholeCoreBridge;
        address wormholeRelayerAddr;
        address specialRelayerAddr;
        uint8 consistencyLevel;
        uint256 gasLimit;
        uint64 outboundLimit;
    }

    function setUp() public {}

    // The minimum gas limit to verify a message on mainnet. If you're worried about saving
    // gas on testnet, pick up the phone and start dialing!
    uint256 constant MIN_WORMHOLE_GAS_LIMIT = 150000;

    /// @notice Deploys the NttManager Proxy contract and initializes the implementation.
    function deployNttManager(DeploymentParams memory params) internal returns (address) {
        // Deploy the Manager Implementation.
        NttManager implementation = new NttManager(
            params.token, params.mode, params.wormholeChainId, params.rateLimitDuration
        );

        // NttManager Proxy
        NttManager nttManagerProxy =
            NttManager(address(new ERC1967Proxy(address(implementation), "")));

        nttManagerProxy.initialize();

        console2.log("NttManager deployed at: ", address(nttManagerProxy));

        return address(nttManagerProxy);
    }

    /// @notice Deploys the Wormhole Transceiver Proxy contract and initializes the implementation.
    function deployWormholeTransceiver(
        DeploymentParams memory params,
        address nttManager
    ) public returns (address) {
        // Deploy the Wormhole Transceiver.
        WormholeTransceiver wormholeTransceiver = new WormholeTransceiver(
            nttManager,
            params.wormholeCoreBridge,
            params.wormholeRelayerAddr,
            params.specialRelayerAddr,
            params.consistencyLevel,
            params.gasLimit
        );

        ERC1967Proxy transceiver = new ERC1967Proxy(address(wormholeTransceiver), "");
        WormholeTransceiver(address(transceiver)).initialize();

        console2.log("Wormhole Transceiver deployed at: ", address(wormholeTransceiver));

        return address(transceiver);
    }

    /// @notice Sets the Wormhole Transceiver address and outbound rate limiter limit on the NttManager.
    function configureNttManger(
        address nttManager,
        address transceiver,
        uint64 outboundLimit
    ) public {
        INttManager(nttManager).setTransceiver(transceiver);
        INttManager(nttManager).setOutboundLimit(outboundLimit);
        INttManager(nttManager).setThreshold(1);
    }

    function _readEnvVariables() internal view returns (DeploymentParams memory params) {
        // Token address.
        params.token = vm.envAddress("RELEASE_TOKEN_ADDRESS");
        require(params.token != address(0), "Invalid token address");

        // Mode.
        uint8 mode = uint8(vm.envUint("RELEASE_MODE"));
        if (mode == 0) {
            params.mode = INttManager.Mode.LOCKING;
        } else if (mode == 1) {
            params.mode = INttManager.Mode.BURNING;
        } else {
            revert("Invalid mode");
        }

        // Chain ID.
        params.wormholeChainId = uint16(vm.envUint("RELEASE_WORMHOLE_CHAIN_ID"));
        require(params.wormholeChainId != 0, "Invalid chain ID");

        // Rate limit duration.
        params.rateLimitDuration = uint64(vm.envUint("RELEASE_RATE_LIMIT_DURATION"));

        // Wormhole Core Bridge address.
        params.wormholeCoreBridge = vm.envAddress("RELEASE_CORE_BRIDGE_ADDRESS");
        require(params.wormholeCoreBridge != address(0), "Invalid wormhole core bridge address");

        // Wormhole relayer, special relayer, consistency level.
        params.wormholeRelayerAddr = vm.envAddress("RELEASE_WORMHOLE_RELAYER_ADDRESS");
        params.specialRelayerAddr = vm.envAddress("RELEASE_SPECIAL_RELAYER_ADDRESS");
        params.consistencyLevel = uint8(vm.envUint("RELEASE_CONSISTENCY_LEVEL"));

        params.gasLimit = vm.envUint("RELEASE_GAS_LIMIT");
        require(params.gasLimit >= MIN_WORMHOLE_GAS_LIMIT, "Invalid gas limit");

        // Outbound rate limiter limit.
        params.outboundLimit = uint64(vm.envUint("RELEASE_OUTBOUND_LIMIT"));
    }

    function run() public {
        vm.startBroadcast(vm.envUint("k"));

        // Sanity check deployment parameters.
        DeploymentParams memory params = _readEnvVariables();

        // Deploy NttManager.
        address manager = deployNttManager(params);

        // Deploy Wormhole Transceiver.
        address transceiver = deployWormholeTransceiver(params, manager);

        // Configure NttManager.
        configureNttManger(manager, transceiver, params.outboundLimit);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {Script, console} from "forge-std/Script.sol";
import {DeployWormholeNttBase} from "./helpers/DeployWormholeNttBase.sol";
import {INttManager} from "../src/interfaces/INttManager.sol";
import {IWormholeTransceiver} from "../src/interfaces/IWormholeTransceiver.sol";
import "../src/interfaces/IManagerBase.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {NttManager} from "../src/NttManager/NttManager.sol";

interface IWormhole {
    function chainId() external view returns (uint16);
}

contract DeployWormholeNtt is Script, DeployWormholeNttBase {
    function run(
        address wormhole,
        address token,
        address wormholeRelayer,
        address specialRelayer,
        IManagerBase.Mode mode
    ) public {
        vm.startBroadcast();

        console.log("Deploying Wormhole Ntt...");
        IWormhole wh = IWormhole(wormhole);

        uint16 chainId = wh.chainId();

        console.log("Chain ID: ", chainId);

        DeploymentParams memory params = DeploymentParams({
            token: token,
            mode: mode,
            wormholeChainId: chainId,
            rateLimitDuration: 86400,
            shouldSkipRatelimiter: false,
            wormholeCoreBridge: wormhole,
            wormholeRelayerAddr: wormholeRelayer,
            specialRelayerAddr: specialRelayer,
            consistencyLevel: 202,
            gasLimit: 500000,
            outboundLimit: uint256(type(uint64).max) * 10 ** 10
        });

        // Deploy NttManager.
        address manager = deployNttManager(params);

        // Deploy Wormhole Transceiver.
        address transceiver = deployWormholeTransceiver(params, manager);

        // Configure NttManager.
        configureNttManager(
            manager, transceiver, params.outboundLimit, params.shouldSkipRatelimiter
        );

        vm.stopBroadcast();
    }

    function upgrade(address manager) public {
        vm.startBroadcast();

        NttManager nttManager = NttManager(manager);

        console.log("Upgrading manager...");

        uint64 rateLimitDuration = nttManager.rateLimitDuration();
        bool shouldSkipRatelimiter = rateLimitDuration == 0;

        NttManager implementation = new NttManager(
            nttManager.token(),
            nttManager.mode(),
            nttManager.chainId(),
            nttManager.rateLimitDuration(),
            shouldSkipRatelimiter
        );

        nttManager.upgrade(address(implementation));

        vm.stopBroadcast();
    }
}

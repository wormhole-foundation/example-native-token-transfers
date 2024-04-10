// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {DeployWormholeNttBase} from "./helpers/DeployWormholeNttBase.sol";

contract DeployWormholeNtt is Script, DeployWormholeNttBase {
    function run() public {
        vm.startBroadcast();

        // Sanity check deployment parameters.
        DeploymentParams memory params = _readEnvVariables();

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
}

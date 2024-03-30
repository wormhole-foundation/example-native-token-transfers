// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {console2} from "forge-std/Script.sol";

import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IManagerBase.sol";

import {NttManager} from "../src/NttManager/NttManager.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ParseNttConfig} from "./helpers/ParseNttConfig.sol";

contract SetOutboundLimit is ParseNttConfig {
    struct Limit {
        uint16 wormholeChainId;
        uint256 outboundLimit;
    }

    function setOutboundLimit(
        address nttManager,
        Limit memory limit
    ) internal {
        console2.log("NttManager Implementation deployed at: ", address(nttManager));

        // Upgrade the proxy.
        INttManager(nttManager).setOutboundLimit(limit.outboundLimit);
    }

    function _readEnvVariables() internal view returns (Limit memory params) {
        // Chain ID.
        params.wormholeChainId = uint16(vm.envUint("RELEASE_WORMHOLE_CHAIN_ID"));
        require(params.wormholeChainId != 0, "Invalid chain ID");

        // Rate limit duration.
        params.outboundLimit = uint256(vm.envUint("RELEASE_OUTBOUND_LIMIT"));
        console2.log("Outbound limit : ", params.outboundLimit);
    }

    function run() public {
        vm.startBroadcast();

        // Sanity check deployment parameters.
        Limit memory params = _readEnvVariables();

        (, INttManager nttManager,) = _parseAndValidateConfigFile(params.wormholeChainId);
        // set outbound limit for the manager on the corersponding chain .
        setOutboundLimit(address(nttManager), params);

        vm.stopBroadcast();
    }
}

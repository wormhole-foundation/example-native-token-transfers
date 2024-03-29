// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {console2} from "forge-std/Script.sol";

import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IManagerBase.sol";

import {NttManager} from "../src/NttManager/NttManager.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ParseNttConfig} from "./helpers/ParseNttConfig.sol";

contract SetLimit is ParseNttConfig {
    struct Limit {
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
        // Rate limit duration.
        params.outboundLimit = uint256(vm.envUint("RELEASE_OUTBOUND_LIMIT"));
        console2.log("Outbound limit duration: ", params.outboundLimit);
    }

    function run() public {
        vm.startBroadcast();

        // Sanity check deployment parameters.
        Limit memory params = _readEnvVariables();

        // TODO: don't hardcode this
        address nttManager = 0x0e313085Aa613DF7594a524F5eA2E3F196F27e92;
        // set outbound limit for the manager on the corersponding chain .
        setOutboundLimit(nttManager, params);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "../../src/interfaces/INttManager.sol";
import "../../src/interfaces/IWormholeTransceiver.sol";

contract ParseNttConfig is Script {
    using stdJson for string;

    struct ChainConfig {
        uint16 chainId;
        uint8 decimals;
        uint64 inboundLimit;
        bool isEvmChain;
        bool isSpecialRelayingEnabled;
        bool isWormholeRelayingEnabled;
        address nttManager;
        address wormholeTransceiver;
    }

    mapping(uint16 => bool) duplicateChainIds;

    function toUniversalAddress(address evmAddr) internal pure returns (bytes32 converted) {
        assembly ("memory-safe") {
            converted := and(0xffffffffffffffffffffffffffffffffffffffff, evmAddr)
        }
    }

    function _parseAndValidateConfigFile(uint16 wormholeChainId)
        internal
        returns (
            ChainConfig[] memory config,
            INttManager nttManager,
            IWormholeTransceiver wormholeTransceiver
        )
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/cfg/WormholeNttConfig.json");
        string memory json = vm.readFile(path);
        bytes memory contracts = json.parseRaw(".contracts");

        // Decode the json into ChainConfig array.
        config = abi.decode(contracts, (ChainConfig[]));

        // Validate values and set the contract addresses for this chain.
        for (uint256 i = 0; i < config.length; i++) {
            require(config[i].chainId != 0, "Invalid chain ID");
            require(config[i].nttManager != address(0), "Invalid NTT manager address");
            require(
                config[i].wormholeTransceiver != address(0), "Invalid wormhole transceiver address"
            );
            require(config[i].inboundLimit != 0, "Invalid inbound limit");

            // Make sure we don't configure the same chain twice.
            require(!duplicateChainIds[config[i].chainId], "Duplicate chain ID");
            duplicateChainIds[config[i].chainId] = true;

            // Set the contract addresses for this chain.
            if (config[i].chainId == wormholeChainId) {
                nttManager = INttManager(config[i].nttManager);
                wormholeTransceiver = IWormholeTransceiver(config[i].wormholeTransceiver);
            }
        }
    }
}

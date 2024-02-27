// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IWormholeTransceiver.sol";
import "../src/interfaces/IOwnableUpgradeable.sol";

import {WormholeTransceiver} from "../src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";

contract ConfigureWormholeNtt is Script {
    using stdJson for string;

    struct ConfigParams {
        uint16 wormholeChainId;
    }

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

    INttManager nttManager;
    IWormholeTransceiver wormholeTransceiver;

    function toUniversalAddress(address evmAddr) internal pure returns (bytes32 converted) {
        assembly ("memory-safe") {
            converted := and(0xffffffffffffffffffffffffffffffffffffffff, evmAddr)
        }
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        // Chain ID.
        params.wormholeChainId = uint16(vm.envUint("RELEASE_WORMHOLE_CHAIN_ID"));
        require(params.wormholeChainId != 0, "Invalid chain ID");
    }

    function _parseAndValidateConfigFile(ConfigParams memory params)
        internal
        returns (ChainConfig[] memory config)
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

            if (config[i].chainId == params.wormholeChainId) {
                nttManager = INttManager(config[i].nttManager);
                wormholeTransceiver = IWormholeTransceiver(config[i].wormholeTransceiver);
            }
        }
    }

    function configureWormholeTransceiver(
        ChainConfig[] memory config,
        ConfigParams memory params
    ) internal {
        for (uint256 i = 0; i < config.length; i++) {
            ChainConfig memory targetConfig = config[i];
            if (targetConfig.chainId == params.wormholeChainId) {
                continue;
            } else {
                // Set relayer.
                if (targetConfig.isWormholeRelayingEnabled) {
                    wormholeTransceiver.setIsWormholeRelayingEnabled(targetConfig.chainId, true);
                    console2.log("Wormhole relaying enabled for chain", targetConfig.chainId);
                } else if (targetConfig.isSpecialRelayingEnabled) {
                    wormholeTransceiver.setIsSpecialRelayingEnabled(targetConfig.chainId, true);
                    console2.log("Special relaying enabled for chain", targetConfig.chainId);
                }

                // Set peer.
                wormholeTransceiver.setWormholePeer(
                    targetConfig.chainId, toUniversalAddress(targetConfig.wormholeTransceiver)
                );
                console2.log("Wormhole peer set for chain", targetConfig.chainId);

                // Set EVM chain.
                if (targetConfig.isEvmChain) {
                    wormholeTransceiver.setIsWormholeEvmChain(targetConfig.chainId);
                    console2.log("EVM chain set for chain", targetConfig.chainId);
                } else {
                   revert("Non-EVM chain is not supported yet");
                }
            }
        }
    }

    function configureNttManager(ChainConfig[] memory config, ConfigParams memory params) internal {
        for (uint256 i = 0; i < config.length; i++) {
            ChainConfig memory targetConfig = config[i];
            if (targetConfig.chainId == params.wormholeChainId) {
                continue;
            } else {
                // Set peer.
                nttManager.setPeer(
                    targetConfig.chainId, toUniversalAddress(targetConfig.nttManager), targetConfig.decimals
                );
                console2.log("Peer set for chain", targetConfig.chainId);

                // Configure the inbound limit.
                nttManager.setInboundLimit(targetConfig.inboundLimit, targetConfig.chainId);
                console2.log("Inbound limit set for chain ", targetConfig.chainId);
            }
        }
    }

    function run() public {
        vm.startBroadcast();

        // Sanity check deployment parameters.
        ConfigParams memory params = _readEnvVariables();
        ChainConfig[] memory config = _parseAndValidateConfigFile(params);

        configureWormholeTransceiver(config, params);
        configureNttManager(config, params);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.0 <0.9.0;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import "./WormholeEndpoint.sol";
import "./EndpointStandalone.sol";

// TODO: we shouldn't use Ownable from openzeppelin as it uses a non-deterministic storage slot
contract WormholeEndpointStandalone is WormholeEndpoint, EndpointStandalone, Ownable {
    constructor(
        address manager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr
    ) EndpointStandalone(manager) WormholeEndpoint(wormholeCoreBridge, wormholeRelayerAddr) {}

    function setWormholeSibling(
        uint16 siblingChainId,
        bytes32 siblingContract
    ) external onlyOwner {
        _setWormholeSibling(siblingChainId, siblingContract);
    }

    function setIsWormholeRelayingEnabled(uint16 chainId, bool isEnabled) external onlyOwner {
        _setIsWormholeRelayingEnabled(chainId, isEnabled);
    }

    function setIsWormholeEvmChain(uint16 chainId) external onlyOwner {
        _setIsWormholeEvmChain(chainId);
    }
}

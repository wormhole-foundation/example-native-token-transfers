// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./WormholeEndpoint.sol";
import "./EndpointStandalone.sol";

contract WormholeEndpointStandalone is WormholeEndpoint, EndpointStandalone {
    constructor(
        address manager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr
    ) EndpointStandalone(manager) WormholeEndpoint(wormholeCoreBridge, wormholeRelayerAddr) {}

    function pauseWormholeEndpoint() external onlyOwner {
        _pauseWormholeEndpoint();
    }

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

    function pauseEndpoint() external override onlyOwnerOrPauser {
        _pause();
    }
}

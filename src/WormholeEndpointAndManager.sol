// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./EndpointAndManager.sol";
import "./WormholeEndpoint.sol";

contract WormholeEndpointAndManager is EndpointAndManager, WormholeEndpoint {
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint256 rateLimitDuration,
        address wormholeCoreBridge,
        address wormholeRelayerAddr
    )
        EndpointAndManager(token, mode, chainId, rateLimitDuration)
        WormholeEndpoint(wormholeCoreBridge, wormholeRelayerAddr)
    {}

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

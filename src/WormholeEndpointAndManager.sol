// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./EndpointAndManager.sol";
import "./WormholeEndpoint.sol";

contract WormholeEndpointAndManager is EndpointAndManager, WormholeEndpoint {
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration,
        address wormholeCoreBridge,
        address wormholeRelayerAddr
    )
        EndpointAndManager(token, mode, chainId, rateLimitDuration)
        WormholeEndpoint(wormholeCoreBridge, wormholeRelayerAddr)
    {}

    function setSibling(uint16 siblingChainId, bytes32 siblingContract) public override onlyOwner {
        super.setSibling(siblingChainId, siblingContract);
        _setWormholeSibling(siblingChainId, siblingContract);
    }

    function setIsWormholeRelayingEnabled(uint16 chainId, bool isEnabled) external onlyOwner {
        _setIsWormholeRelayingEnabled(chainId, isEnabled);
    }

    function setIsWormholeEvmChain(uint16 chainId) external onlyOwner {
        _setIsWormholeEvmChain(chainId);
    }
}

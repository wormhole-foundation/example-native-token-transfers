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
}

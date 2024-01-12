// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "./EndpointAndManager.sol";
import "./WormholeEndpoint.sol";

contract WormholeEndpointAndManager is EndpointAndManager, WormholeEndpoint {
    constructor(
        address token,
        bool isLockingMode,
        uint16 chainId,
        uint256 evmChainId,
        address wormholeCoreBridge,
        address wormholeRelayerAddr
    )
        EndpointAndManager(token, isLockingMode, chainId, evmChainId)
        WormholeEndpoint(wormholeCoreBridge, wormholeRelayerAddr, evmChainId)
    {}
}

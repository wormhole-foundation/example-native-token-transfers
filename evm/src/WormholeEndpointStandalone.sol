// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import "./WormholeEndpoint.sol";
import "./EndpointStandalone.sol";

contract WormholeEndpointStandalone is
    WormholeEndpoint,
    EndpointStandalone,
    Ownable
{
    constructor(
        address manager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        uint256 evmChainId
    )
        EndpointStandalone(manager)
        WormholeEndpoint(wormholeCoreBridge, wormholeRelayerAddr, evmChainId)
    {}
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./WormholeEndpoint.sol";
import "./EndpointStandalone.sol";
import "./Pausable.sol";

contract WormholeEndpointStandalone is WormholeEndpoint, EndpointStandalone {
    constructor(
        address manager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr
    ) EndpointStandalone(manager) WormholeEndpoint(wormholeCoreBridge, wormholeRelayerAddr) {}

    /// @notice This function is used to pause the endpoint
    /// Only the implementor (deployer) can call this function
    function pauseEndpoint() external onlyOwner {
        _pause();
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

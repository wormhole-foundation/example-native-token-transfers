// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import "./WormholeEndpoint.sol";
import "./EndpointStandalone.sol";
import "./Pausable.sol";

// TODO: we shouldn't use Ownable from openzeppelin as it uses a non-deterministic storage slot
contract WormholeEndpointStandalone is WormholeEndpoint, EndpointStandalone, Ownable, Pausable {
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

    function pauseEndpoint() external override onlyOwner {
        _pause();
    }
}

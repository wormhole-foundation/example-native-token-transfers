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

    /// @dev Override the [`transferOwnership`] method from OwnableUpgradeable
    /// to ensure owner cannot transfer ownership
    function transferOwnership(address newOwner) public override onlyOwner {
        // do nothing
        // this method body is empty
    }

    /// @dev Override the [`renounceOwnership`] function to ensure
    /// the manager ownership is not renounced.
    function renounceOwnership() public override onlyOwner {
        // do nothing
        // this method body is empty
    }
}

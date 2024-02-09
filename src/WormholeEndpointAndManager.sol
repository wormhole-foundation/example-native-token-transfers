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

    /// @notice This function is used to pause the manager and the endpoint
    function pause() public override onlyOwner {
        // pause the manager
        super.pause();
        // pause the endpoint
        _pauseWormholeEndpoint();
    }

    function setIsWormholeRelayingEnabled(uint16 chainId, bool isEnabled) external onlyOwner {
        _setIsWormholeRelayingEnabled(chainId, isEnabled);
    }

    function setIsWormholeEvmChain(uint16 chainId) external onlyOwner {
        _setIsWormholeEvmChain(chainId);
    }

    /// @dev Override the [`renounceOwnership`] function to ensure
    /// the manager ownership is not renounced.
    function renounceOwnership() public view override onlyOwner {
        revert CannotRenounceManagerOwnership(owner());
    }
}

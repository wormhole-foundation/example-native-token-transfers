// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./WormholeEndpoint.sol";
import "./EndpointStandalone.sol";

contract WormholeEndpointStandalone is WormholeEndpoint, EndpointStandalone {
    constructor(
        address manager,
        address wormholeCoreBridge,
        address wormholeRelayerAddr,
        address specialRelayerAddr
    )
        EndpointStandalone(manager)
        WormholeEndpoint(wormholeCoreBridge, wormholeRelayerAddr, specialRelayerAddr)
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

    function pauseEndpoint() external override onlyOwnerOrPauser {
        _pause();
    }

    /// @dev Override the [`transferOwnership`] method from OwnableUpgradeable
    /// to ensure owner of this contract is in sync with the onwer of the Manager contract.
    function transferOwnership(address newOwner) public view override onlyOwner {
        revert CannotTransferEndpointOwnership(owner(), newOwner);
    }

    /// @dev Override the [`renounceOwnership`] function to ensure
    /// the endpoint ownership is not renounced.
    function renounceOwnership() public view override onlyOwner {
        revert CannotRenounceEndpointOwnership(owner());
    }
}

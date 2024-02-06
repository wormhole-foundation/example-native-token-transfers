// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.0 <0.9.0;

error InvalidFork(uint256 evmChainId, uint256 blockChainId);

function checkFork(uint256 evmChainId) view {
    if (isFork(evmChainId)) {
        revert InvalidFork(evmChainId, block.chainid);
    }
}

function isFork(uint256 evmChainId) view returns (bool) {
    return evmChainId != block.chainid;
}

function min(uint256 a, uint256 b) pure returns (uint256) {
    return a < b ? a : b;
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

uint256 constant FALSE = 0;
uint256 constant TRUE = 1;

error InvalidBoolValue(uint256 value);

function toBool(uint256 value) pure returns (bool) {
    if (value == 0) return false;
    if (value == 1) return true;
    revert InvalidBoolValue(value);
}

function toWord(bool value) pure returns (uint256) {
    if (value) {
        return TRUE;
    } else {
        return FALSE;
    }
}

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

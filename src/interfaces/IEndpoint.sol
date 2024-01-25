// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

interface IEndpoint {
    error InvalidSiblingZeroAddress();

    function getSibling(uint16 chainId) external view returns (bytes32);
}

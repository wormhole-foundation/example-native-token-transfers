// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.0 <0.9.0;

interface IEndpointToken {
    function mint(address account, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

interface INTTToken {
    error CallerNotMinter(address caller);
    error InvalidMinterZeroAddress();

    event NewMinter(address newMinter);

    function mint(address account, uint256 amount) external;
    function setMinter(address newMinter) external;
}

pragma solidity >=0.8.8 <0.9.0;

interface IHevm {
    function prank(address) external;

    function warp(uint256 newTimestamp) external;
}
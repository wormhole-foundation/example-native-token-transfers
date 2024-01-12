// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

interface IEndpointManagerStandalone {
    error NotImplemented();

    function attestationReceived(bytes memory payload) external;

    function getThreshold() external view returns (uint8);

    function getEndpoints() external view returns (address[] memory);
}

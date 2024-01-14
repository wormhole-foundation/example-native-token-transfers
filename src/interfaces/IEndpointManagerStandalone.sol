// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "../libraries/EndpointStructs.sol";

interface IEndpointManagerStandalone {
    error NotImplemented();

    function attestationReceived(EndpointStructs.EndpointManagerMessage memory payload) external;

    function getThreshold() external view returns (uint8);

    function getEndpoints() external view returns (address[] memory);
}

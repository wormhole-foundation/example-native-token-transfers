// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "../libraries/EndpointStructs.sol";

interface IEndpointManagerStandalone {
    error NotImplemented();

    error ZeroThreshold();
    error ThresholdTooHigh(uint256 threshold, uint256 endpoints);

    function attestationReceived(EndpointStructs.EndpointManagerMessage memory payload) external;
}

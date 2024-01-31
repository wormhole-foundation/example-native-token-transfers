// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "../libraries/EndpointStructs.sol";

interface IManagerStandalone {
    error ZeroThreshold();
    error ThresholdTooHigh(uint256 threshold, uint256 endpoints);

    function attestationReceived(EndpointStructs.ManagerMessage memory payload) external;

    function upgrade(address newImplementation) external;

    function upgradeEndpoint(address endpoint, address newImplementation) external;
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/EndpointStructs.sol";

interface IManagerStandalone {
    error ZeroThreshold();
    error ThresholdTooHigh(uint256 threshold, uint256 endpoints);
    error RetrievedIncorrectRegisteredEndpoints(uint256 retrieved, uint256 registered);

    function attestationReceived(
        uint16 sourceChainId,
        bytes32 sourceManagerAddress,
        EndpointStructs.ManagerMessage memory payload
    ) external;

    function upgrade(address newImplementation) external;
}

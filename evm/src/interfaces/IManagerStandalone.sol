// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "../libraries/TransceiverStructs.sol";

interface IManagerStandalone {
    error ZeroThreshold();
    error ThresholdTooHigh(uint256 threshold, uint256 transceivers);
    error RetrievedIncorrectRegisteredTransceivers(uint256 retrieved, uint256 registered);

    function attestationReceived(
        uint16 sourceChainId,
        bytes32 sourceManagerAddress,
        TransceiverStructs.ManagerMessage memory payload
    ) external;

    function upgrade(address newImplementation) external;
}

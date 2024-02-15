// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

interface IEndpointReceiver {
    function receiveMessage(bytes memory encodedMessage) external;
}

// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "./ManagerHelpers.sol";
import "../mocks/DummyEndpoint.sol";
import "../mocks/DummyToken.sol";
import "../../src/ManagerStandalone.sol";
import "../../src/libraries/NormalizedAmount.sol";

library EndpointHelpersLib {
    using NormalizedAmountLib for NormalizedAmount;

    // 0x99'E''T''T'
    bytes4 constant TEST_ENDPOINT_PAYLOAD_PREFIX = 0x99455454;
    uint16 constant SENDING_CHAIN_ID = 1;

    function setup_endpoints(ManagerStandalone manager)
        internal
        returns (DummyEndpoint, DummyEndpoint)
    {
        DummyEndpoint e1 = new DummyEndpoint(address(manager));
        DummyEndpoint e2 = new DummyEndpoint(address(manager));
        manager.setEndpoint(address(e1));
        manager.setEndpoint(address(e2));
        manager.setThreshold(2);
        return (e1, e2);
    }

    function attestEndpointsHelper(
        address to,
        uint64 sequence,
        uint16 toChain,
        ManagerStandalone manager,
        NormalizedAmount memory amount,
        NormalizedAmount memory inboundLimit,
        IEndpointReceiver[] memory endpoints
    )
        internal
        returns (EndpointStructs.ManagerMessage memory, EndpointStructs.EndpointMessage memory)
    {
        EndpointStructs.ManagerMessage memory m =
            buildManagerMessage(to, sequence, toChain, manager, amount);
        bytes memory encodedM = EndpointStructs.encodeManagerMessage(m);

        prepTokenReceive(manager, amount, inboundLimit);

        EndpointStructs.EndpointMessage memory em;
        bytes memory encodedEm;
        (em, encodedEm) = EndpointStructs.buildAndEncodeEndpointMessage(
            TEST_ENDPOINT_PAYLOAD_PREFIX, toWormholeFormat(address(manager)), encodedM, new bytes(0)
        );

        for (uint256 i; i < endpoints.length; i++) {
            IEndpointReceiver e = endpoints[i];
            e.receiveMessage(encodedEm);
        }

        return (m, em);
    }

    function buildManagerMessage(
        address to,
        uint64 sequence,
        uint16 toChain,
        ManagerStandalone manager,
        NormalizedAmount memory amount
    ) internal view returns (EndpointStructs.ManagerMessage memory) {
        DummyToken token = DummyToken(manager.token());

        return EndpointStructs.ManagerMessage(
            sequence,
            bytes32(0),
            EndpointStructs.encodeNativeTokenTransfer(
                EndpointStructs.NativeTokenTransfer({
                    amount: amount,
                    sourceToken: toWormholeFormat(address(token)),
                    to: toWormholeFormat(to),
                    toChain: toChain
                })
            )
        );
    }

    function prepTokenReceive(
        ManagerStandalone manager,
        NormalizedAmount memory amount,
        NormalizedAmount memory inboundLimit
    ) internal {
        DummyToken token = DummyToken(manager.token());
        token.mintDummy(address(manager), amount.denormalize(token.decimals()));
        ManagerHelpersLib.setConfigs(inboundLimit, manager, token.decimals());
    }

    function buildEndpointMessageWithManagerPayload(
        uint64 sequence,
        bytes32 sender,
        bytes32 sourceManager,
        bytes memory payload
    ) internal pure returns (EndpointStructs.ManagerMessage memory, bytes memory) {
        EndpointStructs.ManagerMessage memory m =
            EndpointStructs.ManagerMessage(sequence, sender, payload);
        bytes memory managerMessage = EndpointStructs.encodeManagerMessage(m);
        bytes memory endpointMessage;
        (, endpointMessage) = EndpointStructs.buildAndEncodeEndpointMessage(
            TEST_ENDPOINT_PAYLOAD_PREFIX, sourceManager, managerMessage, new bytes(0)
        );
        return (m, endpointMessage);
    }
}

// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "./ManagerHelpers.sol";
import "../mocks/DummyTransceiver.sol";
import "../mocks/DummyToken.sol";
import "../../src/Manager.sol";
import "../../src/libraries/NormalizedAmount.sol";

library TransceiverHelpersLib {
    using NormalizedAmountLib for NormalizedAmount;

    // 0x99'E''T''T'
    bytes4 constant TEST_TRANSCEIVER_PAYLOAD_PREFIX = 0x99455454;
    uint16 constant SENDING_CHAIN_ID = 1;

    function setup_transceivers(Manager manager)
        internal
        returns (DummyTransceiver, DummyTransceiver)
    {
        DummyTransceiver e1 = new DummyTransceiver(address(manager));
        DummyTransceiver e2 = new DummyTransceiver(address(manager));
        manager.setTransceiver(address(e1));
        manager.setTransceiver(address(e2));
        manager.setThreshold(2);
        return (e1, e2);
    }

    function attestTransceiversHelper(
        address to,
        uint64 sequence,
        uint16 toChain,
        Manager manager,
        Manager recipientManager,
        NormalizedAmount memory amount,
        NormalizedAmount memory inboundLimit,
        ITransceiverReceiver[] memory transceivers
    )
        internal
        returns (
            TransceiverStructs.ManagerMessage memory,
            TransceiverStructs.TransceiverMessage memory
        )
    {
        TransceiverStructs.ManagerMessage memory m =
            buildManagerMessage(to, sequence, toChain, manager, amount);
        bytes memory encodedM = TransceiverStructs.encodeManagerMessage(m);

        prepTokenReceive(manager, recipientManager, amount, inboundLimit);

        TransceiverStructs.TransceiverMessage memory em;
        bytes memory encodedEm;
        (em, encodedEm) = TransceiverStructs.buildAndEncodeTransceiverMessage(
            TEST_TRANSCEIVER_PAYLOAD_PREFIX,
            toWormholeFormat(address(manager)),
            toWormholeFormat(address(recipientManager)),
            encodedM,
            new bytes(0)
        );

        for (uint256 i; i < transceivers.length; i++) {
            ITransceiverReceiver e = transceivers[i];
            e.receiveMessage(encodedEm);
        }

        return (m, em);
    }

    function buildManagerMessage(
        address to,
        uint64 sequence,
        uint16 toChain,
        Manager manager,
        NormalizedAmount memory amount
    ) internal view returns (TransceiverStructs.ManagerMessage memory) {
        DummyToken token = DummyToken(manager.token());

        return TransceiverStructs.ManagerMessage(
            sequence,
            bytes32(0),
            TransceiverStructs.encodeNativeTokenTransfer(
                TransceiverStructs.NativeTokenTransfer({
                    amount: amount,
                    sourceToken: toWormholeFormat(address(token)),
                    to: toWormholeFormat(to),
                    toChain: toChain
                })
            )
        );
    }

    function prepTokenReceive(
        Manager manager,
        Manager recipientManager,
        NormalizedAmount memory amount,
        NormalizedAmount memory inboundLimit
    ) internal {
        DummyToken token = DummyToken(manager.token());
        token.mintDummy(address(recipientManager), amount.denormalize(token.decimals()));
        ManagerHelpersLib.setConfigs(inboundLimit, manager, recipientManager, token.decimals());
    }

    function buildTransceiverMessageWithManagerPayload(
        uint64 sequence,
        bytes32 sender,
        bytes32 sourceManager,
        bytes32 recipientManager,
        bytes memory payload
    ) internal pure returns (TransceiverStructs.ManagerMessage memory, bytes memory) {
        TransceiverStructs.ManagerMessage memory m =
            TransceiverStructs.ManagerMessage(sequence, sender, payload);
        bytes memory managerMessage = TransceiverStructs.encodeManagerMessage(m);
        bytes memory transceiverMessage;
        (, transceiverMessage) = TransceiverStructs.buildAndEncodeTransceiverMessage(
            TEST_TRANSCEIVER_PAYLOAD_PREFIX,
            sourceManager,
            recipientManager,
            managerMessage,
            new bytes(0)
        );
        return (m, transceiverMessage);
    }
}

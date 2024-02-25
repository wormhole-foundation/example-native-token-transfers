// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "./NttManagerHelpers.sol";
import "../mocks/DummyTransceiver.sol";
import "../mocks/DummyToken.sol";
import "../../src/NttManager.sol";
import "../../src/libraries/NormalizedAmount.sol";

library TransceiverHelpersLib {
    using NormalizedAmountLib for NormalizedAmount;

    // 0x99'E''T''T'
    bytes4 constant TEST_TRANSCEIVER_PAYLOAD_PREFIX = 0x99455454;
    uint16 constant SENDING_CHAIN_ID = 1;

    function setup_transceivers(NttManager nttManager)
        internal
        returns (DummyTransceiver, DummyTransceiver)
    {
        DummyTransceiver e1 = new DummyTransceiver(address(nttManager));
        DummyTransceiver e2 = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e1));
        nttManager.setTransceiver(address(e2));
        nttManager.setThreshold(2);
        return (e1, e2);
    }

    function attestTransceiversHelper(
        address to,
        uint64 sequence,
        uint16 toChain,
        NttManager nttManager,
        NttManager recipientNttManager,
        NormalizedAmount memory amount,
        NormalizedAmount memory inboundLimit,
        ITransceiverReceiver[] memory transceivers
    )
        internal
        returns (
            TransceiverStructs.NttManagerMessage memory,
            TransceiverStructs.TransceiverMessage memory
        )
    {
        TransceiverStructs.NttManagerMessage memory m =
            buildNttManagerMessage(to, sequence, toChain, nttManager, amount);
        bytes memory encodedM = TransceiverStructs.encodeNttManagerMessage(m);

        prepTokenReceive(nttManager, recipientNttManager, amount, inboundLimit);

        TransceiverStructs.TransceiverMessage memory em;
        bytes memory encodedEm;
        (em, encodedEm) = TransceiverStructs.buildAndEncodeTransceiverMessage(
            TEST_TRANSCEIVER_PAYLOAD_PREFIX,
            toWormholeFormat(address(nttManager)),
            toWormholeFormat(address(recipientNttManager)),
            encodedM,
            new bytes(0)
        );

        for (uint256 i; i < transceivers.length; i++) {
            ITransceiverReceiver e = transceivers[i];
            e.receiveMessage(encodedEm);
        }

        return (m, em);
    }

    function buildNttManagerMessage(
        address to,
        uint64 sequence,
        uint16 toChain,
        NttManager nttManager,
        NormalizedAmount memory amount
    ) internal view returns (TransceiverStructs.NttManagerMessage memory) {
        DummyToken token = DummyToken(nttManager.token());

        return TransceiverStructs.NttManagerMessage(
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
        NttManager nttManager,
        NttManager recipientNttManager,
        NormalizedAmount memory amount,
        NormalizedAmount memory inboundLimit
    ) internal {
        DummyToken token = DummyToken(nttManager.token());
        token.mintDummy(address(recipientNttManager), amount.denormalize(token.decimals()));
        NttManagerHelpersLib.setConfigs(
            inboundLimit, nttManager, recipientNttManager, token.decimals()
        );
    }

    function buildTransceiverMessageWithNttManagerPayload(
        uint64 sequence,
        bytes32 sender,
        bytes32 sourceNttManager,
        bytes32 recipientNttManager,
        bytes memory payload
    ) internal pure returns (TransceiverStructs.NttManagerMessage memory, bytes memory) {
        TransceiverStructs.NttManagerMessage memory m =
            TransceiverStructs.NttManagerMessage(sequence, sender, payload);
        bytes memory nttManagerMessage = TransceiverStructs.encodeNttManagerMessage(m);
        bytes memory transceiverMessage;
        (, transceiverMessage) = TransceiverStructs.buildAndEncodeTransceiverMessage(
            TEST_TRANSCEIVER_PAYLOAD_PREFIX,
            sourceNttManager,
            recipientNttManager,
            nttManagerMessage,
            new bytes(0)
        );
        return (m, transceiverMessage);
    }
}

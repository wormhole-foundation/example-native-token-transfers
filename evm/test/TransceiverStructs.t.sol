// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";

import "../src/libraries/TransceiverStructs.sol";
import "../src/WormholeTransceiver.sol";

contract TestTransceiverStructs is Test {
    using NormalizedAmountLib for uint256;
    using NormalizedAmountLib for NormalizedAmount;

    // TODO: add some negative tests for unknown message types etc

    function test_serialize_TransceiverMessage() public {
        TransceiverStructs.NativeTokenTransfer memory ntt = TransceiverStructs.NativeTokenTransfer({
            amount: NormalizedAmount({amount: 1234567, decimals: 7}),
            sourceToken: hex"BEEFFACE",
            to: hex"FEEBCAFE",
            toChain: 17
        });

        TransceiverStructs.ManagerMessage memory mm = TransceiverStructs.ManagerMessage({
            sequence: 233968345345,
            sender: hex"46679213412343",
            payload: TransceiverStructs.encodeNativeTokenTransfer(ntt)
        });

        bytes4 wh_prefix = 0x9945FF10;
        TransceiverStructs.TransceiverMessage memory em = TransceiverStructs.TransceiverMessage({
            sourceManagerAddress: hex"042942FAFABE",
            recipientManagerAddress: hex"042942FABABE",
            managerPayload: TransceiverStructs.encodeManagerMessage(mm),
            transceiverPayload: new bytes(0)
        });

        bytes memory encodedTransceiverMessage =
            TransceiverStructs.encodeTransceiverMessage(wh_prefix, em);

        // this is a useful test case for implementations on other runtimes
        bytes memory encodedExpected =
            hex"9945ff10042942fafabe0000000000000000000000000000000000000000000000000000042942fababe00000000000000000000000000000000000000000000000000000079000000367999a1014667921341234300000000000000000000000000000000000000000000000000004f994e545407000000000012d687beefface00000000000000000000000000000000000000000000000000000000feebcafe0000000000000000000000000000000000000000000000000000000000110000";
        assertEq(encodedTransceiverMessage, encodedExpected);

        TransceiverStructs.TransceiverMessage memory emParsed =
            TransceiverStructs.parseTransceiverMessage(wh_prefix, encodedTransceiverMessage);

        TransceiverStructs.ManagerMessage memory mmParsed =
            TransceiverStructs.parseManagerMessage(emParsed.managerPayload);

        // deep equality check
        assertEq(abi.encode(mmParsed), abi.encode(mm));

        TransceiverStructs.NativeTokenTransfer memory nttParsed =
            TransceiverStructs.parseNativeTokenTransfer(mmParsed.payload);

        // deep equality check
        assertEq(abi.encode(nttParsed), abi.encode(ntt));
    }

    function test_SerdeRoundtrip_ManagerMessage(TransceiverStructs.ManagerMessage memory m)
        public
    {
        bytes memory message = TransceiverStructs.encodeManagerMessage(m);

        TransceiverStructs.ManagerMessage memory parsed =
            TransceiverStructs.parseManagerMessage(message);

        assertEq(m.sequence, parsed.sequence);
        assertEq(m.sender, parsed.sender);
        assertEq(m.payload, parsed.payload);
    }

    function test_SerdeJunk_ManagerMessage(TransceiverStructs.ManagerMessage memory m) public {
        bytes memory message = TransceiverStructs.encodeManagerMessage(m);

        bytes memory junk = "junk";

        vm.expectRevert(
            abi.encodeWithSignature(
                "LengthMismatch(uint256,uint256)", message.length + junk.length, message.length
            )
        );
        TransceiverStructs.parseManagerMessage(abi.encodePacked(message, junk));
    }

    function test_SerdeRoundtrip_NativeTokenTransfer(
        TransceiverStructs.NativeTokenTransfer memory m
    ) public {
        bytes memory message = TransceiverStructs.encodeNativeTokenTransfer(m);

        TransceiverStructs.NativeTokenTransfer memory parsed =
            TransceiverStructs.parseNativeTokenTransfer(message);

        assertEq(m.amount.getAmount(), parsed.amount.getAmount());
        assertEq(m.to, parsed.to);
        assertEq(m.toChain, parsed.toChain);
    }

    function test_SerdeJunk_NativeTokenTransfer(TransceiverStructs.NativeTokenTransfer memory m)
        public
    {
        bytes memory message = TransceiverStructs.encodeNativeTokenTransfer(m);

        bytes memory junk = "junk";

        vm.expectRevert(
            abi.encodeWithSignature(
                "LengthMismatch(uint256,uint256)", message.length + junk.length, message.length
            )
        );
        TransceiverStructs.parseNativeTokenTransfer(abi.encodePacked(message, junk));
    }
}

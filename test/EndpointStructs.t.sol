// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";

import "../src/libraries/EndpointStructs.sol";
import "../src/WormholeEndpoint.sol";

contract TestEndpointStructs is Test {
    using NormalizedAmountLib for uint256;
    using NormalizedAmountLib for NormalizedAmount;

    // TODO: add some negative tests for unknown message types etc

    function test_serialize_EndpointMessage() public {
        EndpointStructs.NativeTokenTransfer memory ntt = EndpointStructs.NativeTokenTransfer({
            amount: NormalizedAmount({amount: 1234567, decimals: 7}),
            sourceToken: hex"BEEFFACE",
            to: hex"FEEBCAFE",
            toChain: 17
        });

        EndpointStructs.ManagerMessage memory mm = EndpointStructs.ManagerMessage({
            sequence: 233968345345,
            sender: hex"46679213412343",
            payload: EndpointStructs.encodeNativeTokenTransfer(ntt)
        });

        bytes4 wh_prefix = 0x9945FF10;
        EndpointStructs.EndpointMessage memory em = EndpointStructs.EndpointMessage({
            sourceManagerAddress: hex"042942FAFABE",
            managerPayload: EndpointStructs.encodeManagerMessage(mm),
            endpointPayload: new bytes(0)
        });

        bytes memory encodedEndpointMessage = EndpointStructs.encodeEndpointMessage(wh_prefix, em);

        // this is a useful test case for implementations on other runtimes
        bytes memory encodedExpected =
            hex"9945ff10042942fafabe00000000000000000000000000000000000000000000000000000079000000367999a1014667921341234300000000000000000000000000000000000000000000000000004f994e545407000000000012d687beefface00000000000000000000000000000000000000000000000000000000feebcafe0000000000000000000000000000000000000000000000000000000000110000";
        assertEq(encodedEndpointMessage, encodedExpected);

        EndpointStructs.EndpointMessage memory emParsed =
            EndpointStructs.parseEndpointMessage(wh_prefix, encodedEndpointMessage);

        EndpointStructs.ManagerMessage memory mmParsed =
            EndpointStructs.parseManagerMessage(emParsed.managerPayload);

        // deep equality check
        assertEq(abi.encode(mmParsed), abi.encode(mm));

        EndpointStructs.NativeTokenTransfer memory nttParsed =
            EndpointStructs.parseNativeTokenTransfer(mmParsed.payload);

        // deep equality check
        assertEq(abi.encode(nttParsed), abi.encode(ntt));
    }

    function test_SerdeRoundtrip_ManagerMessage(EndpointStructs.ManagerMessage memory m) public {
        bytes memory message = EndpointStructs.encodeManagerMessage(m);

        EndpointStructs.ManagerMessage memory parsed = EndpointStructs.parseManagerMessage(message);

        assertEq(m.sequence, parsed.sequence);
        assertEq(m.sender, parsed.sender);
        assertEq(m.payload, parsed.payload);
    }

    function test_SerdeJunk_ManagerMessage(EndpointStructs.ManagerMessage memory m) public {
        bytes memory message = EndpointStructs.encodeManagerMessage(m);

        bytes memory junk = "junk";

        vm.expectRevert(
            abi.encodeWithSignature(
                "LengthMismatch(uint256,uint256)", message.length + junk.length, message.length
            )
        );
        EndpointStructs.parseManagerMessage(abi.encodePacked(message, junk));
    }

    function test_SerdeRoundtrip_NativeTokenTransfer(EndpointStructs.NativeTokenTransfer memory m)
        public
    {
        bytes memory message = EndpointStructs.encodeNativeTokenTransfer(m);

        EndpointStructs.NativeTokenTransfer memory parsed =
            EndpointStructs.parseNativeTokenTransfer(message);

        assertEq(m.amount.getAmount(), parsed.amount.getAmount());
        assertEq(m.to, parsed.to);
        assertEq(m.toChain, parsed.toChain);
    }

    function test_SerdeJunk_NativeTokenTransfer(EndpointStructs.NativeTokenTransfer memory m)
        public
    {
        bytes memory message = EndpointStructs.encodeNativeTokenTransfer(m);

        bytes memory junk = "junk";

        vm.expectRevert(
            abi.encodeWithSignature(
                "LengthMismatch(uint256,uint256)", message.length + junk.length, message.length
            )
        );
        EndpointStructs.parseNativeTokenTransfer(abi.encodePacked(message, junk));
    }
}

// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";

import "../src/libraries/EndpointStructs.sol";

contract TestEndpointStructs is Test {
    using NormalizedAmountLib for uint256;
    using NormalizedAmountLib for NormalizedAmount;

    // TODO: add some negative tests for unknown message types etc

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

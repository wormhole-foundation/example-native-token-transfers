// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "../../src/libraries/TrimmedAmount.sol";
import "../../src/NttManager/NttManager.sol";

library NttManagerHelpersLib {
    uint16 constant SENDING_CHAIN_ID = 1;

    using TrimmedAmountLib for TrimmedAmount;

    function setConfigs(
        TrimmedAmount inboundLimit,
        NttManager nttManager,
        NttManager recipientNttManager,
        uint8 decimals
    ) internal {
        (, bytes memory queriedDecimals) =
            address(nttManager.token()).staticcall(abi.encodeWithSignature("decimals()"));
        uint8 tokenDecimals = abi.decode(queriedDecimals, (uint8));
        recipientNttManager.setPeer(
            SENDING_CHAIN_ID, toWormholeFormat(address(nttManager)), tokenDecimals, type(uint64).max
        );
        recipientNttManager.setInboundLimit(inboundLimit.untrim(decimals), SENDING_CHAIN_ID);
    }

    // naive implementation of countSetBits to test against
    function simpleCount(uint64 n) public pure returns (uint8) {
        uint8 count;

        while (n > 0) {
            count += uint8(n & 1);
            n >>= 1;
        }

        return count;
    }
}

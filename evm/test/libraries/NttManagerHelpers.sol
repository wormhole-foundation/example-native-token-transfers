// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "../../src/libraries/TrimmedAmount.sol";
import "../../src/NttManager.sol";

library NttManagerHelpersLib {
    uint16 constant SENDING_CHAIN_ID = 1;

    using TrimmedAmountLib for TrimmedAmount;

    function setConfigs(
        TrimmedAmount memory inboundLimit,
        NttManager nttManager,
        NttManager recipientNttManager,
        uint8 decimals
    ) internal {
        recipientNttManager.setPeer(SENDING_CHAIN_ID, toWormholeFormat(address(nttManager)));
        recipientNttManager.setInboundLimit(inboundLimit.untrim(decimals), SENDING_CHAIN_ID);
    }
}

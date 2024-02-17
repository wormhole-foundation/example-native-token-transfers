// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "../../src/libraries/NormalizedAmount.sol";
import "../../src/ManagerStandalone.sol";

library ManagerHelpersLib {
    uint16 constant SENDING_CHAIN_ID = 1;

    using NormalizedAmountLib for NormalizedAmount;

    function setConfigs(
        NormalizedAmount memory inboundLimit,
        ManagerStandalone manager,
        uint8 decimals
    ) internal {
        manager.setSibling(SENDING_CHAIN_ID, toWormholeFormat(address(manager)));
        manager.setInboundLimit(inboundLimit.denormalize(decimals), SENDING_CHAIN_ID);
    }
}

// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "../../src/libraries/NormalizedAmount.sol";
import "../../src/Manager.sol";

library ManagerHelpersLib {
    uint16 constant SENDING_CHAIN_ID = 1;

    using NormalizedAmountLib for NormalizedAmount;

    function setConfigs(
        NormalizedAmount memory inboundLimit,
        Manager manager,
        Manager recipientManager,
        uint8 decimals
    ) internal {
        recipientManager.setSibling(SENDING_CHAIN_ID, toWormholeFormat(address(manager)));
        recipientManager.setInboundLimit(inboundLimit.denormalize(decimals), SENDING_CHAIN_ID);
    }
}

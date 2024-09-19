// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./NttManager.sol";

contract NttManagerNoRateLimiting is NttManager {
    constructor(
        address _token,
        Mode _mode,
        uint16 _chainId,
        uint64 _rateLimitDuration,
        bool _skipRateLimiting
    ) NttManager(_token, _mode, _chainId, _rateLimitDuration, _skipRateLimiting) {}


    function _isOutboundAmountRateLimited(
        TrimmedAmount amount
    ) internal override view returns (bool) {
        return false;
    }

}

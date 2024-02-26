// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./libraries/TrimmedAmount.sol";

abstract contract NttTrimmer {
    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    uint8 internal immutable tokenDecimals_;

    constructor(address _token) {
        tokenDecimals_ = _tokenDecimals(_token);
    }

    function _tokenDecimals(address token) internal view returns (uint8) {
        (, bytes memory queriedDecimals) = token.staticcall(abi.encodeWithSignature("decimals()"));
        return abi.decode(queriedDecimals, (uint8));
    }

    function _nttTrimmer(uint256 amount) internal view returns (TrimmedAmount memory) {
        return amount.trim(tokenDecimals_);
    }

    function _nttUntrim(TrimmedAmount memory amount) internal view returns (uint256) {
        return amount.untrim(tokenDecimals_);
    }

    /// @dev Shift decimals of `amount` to match the token decimals
    function _nttFixDecimals(TrimmedAmount memory amount)
        internal
        view
        returns (TrimmedAmount memory)
    {
        return _nttTrimmer(_nttUntrim(amount));
    }
}

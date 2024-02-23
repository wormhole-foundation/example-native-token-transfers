// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./libraries/NormalizedAmount.sol";

abstract contract NttNormalizer {
    using NormalizedAmountLib for uint256;
    using NormalizedAmountLib for NormalizedAmount;

    uint8 immutable tokenDecimals;

    constructor(address _token) {
        tokenDecimals = _tokenDecimals(_token);
    }

    function _tokenDecimals(address token) internal view returns (uint8) {
        (, bytes memory queriedDecimals) = token.staticcall(abi.encodeWithSignature("decimals()"));
        return abi.decode(queriedDecimals, (uint8));
    }

    function _nttNormalize(uint256 amount) internal view returns (NormalizedAmount memory) {
        return amount.normalize(tokenDecimals);
    }

    function _nttDenormalize(NormalizedAmount memory amount) internal view returns (uint256) {
        return amount.denormalize(tokenDecimals);
    }

    /// @dev Shift decimals of `amount` to match the token decimals
    function _nttFixDecimals(NormalizedAmount memory amount)
        internal
        view
        returns (NormalizedAmount memory)
    {
        return _nttNormalize(_nttDenormalize(amount));
    }
}

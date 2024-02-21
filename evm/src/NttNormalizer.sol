// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./libraries/NormalizedAmount.sol";

abstract contract NttNormalizer {
    using NormalizedAmountLib for uint256;
    using NormalizedAmountLib for NormalizedAmount;

    uint8 internal immutable tokenDecimals_;

    constructor(address _token) {
        tokenDecimals_ = _tokenDecimals(_token);
    }

    function _tokenDecimals(address token) internal view returns (uint8) {
        (, bytes memory queriedDecimals) = token.staticcall(abi.encodeWithSignature("decimals()"));
        return abi.decode(queriedDecimals, (uint8));
    }

    function nttNormalize(uint256 amount) public view returns (NormalizedAmount memory) {
        return amount.normalize(tokenDecimals_);
    }

    function nttDenormalize(NormalizedAmount memory amount) public view returns (uint256) {
        return amount.denormalize(tokenDecimals_);
    }

    /// @dev Shift decimals of `amount` to match the token decimals
    function nttFixDecimals(NormalizedAmount memory amount)
        public
        view
        returns (NormalizedAmount memory)
    {
        return nttNormalize(nttDenormalize(amount));
    }
}

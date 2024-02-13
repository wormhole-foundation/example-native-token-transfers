// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {Test} from "forge-std/Test.sol";
import "../src/libraries/NormalizedAmount.sol";

contract NormalizationTest is Test {
    using NormalizedAmountLib for uint256;
    using NormalizedAmountLib for NormalizedAmount;

    function testNormalizationRoundTrip() public {
        uint8 decimals = 18;
        uint256 amount = 50 * 10 ** decimals;
        NormalizedAmount memory normalized = amount.normalize(decimals);
        uint256 roundTrip = normalized.denormalize(decimals);

        uint256 expectedAmount = 50 * 10 ** decimals;
        assertEq(expectedAmount, roundTrip);
    }
}

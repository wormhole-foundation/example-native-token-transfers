// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

interface ISpecialRelayer {
    function quoteDeliveryPrice(
        address sourceContract,
        uint16 targetChain,
        uint256 additionalValue
    ) external view returns (uint256 nativePriceQuote);

    function requestDelivery(
        address sourceContract,
        uint16 targetChain,
        uint256 additionalValue,
        uint64 sequence
    ) external payable;
}

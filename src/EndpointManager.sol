// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "./libraries/external/OwnableUpgradeable.sol";
import "./libraries/EndpointStructs.sol";
import "./libraries/EndpointHelpers.sol";
import "./interfaces/IEndpointManager.sol";
import "./interfaces/IEndpointToken.sol";
import "./Endpoint.sol";

abstract contract EndpointManager is
    IEndpointManager,
    OwnableUpgradeable,
    ReentrancyGuard
{
    using BytesParsing for bytes;

    address immutable _token;
    bool immutable _isLockingMode;
    uint16 immutable _chainId;
    uint256 immutable _evmChainId;

    uint64 _sequence;

    constructor(
        address token,
        bool isLockingMode,
        uint16 chainId,
        uint256 evmChainId
    ) {
        _token = token;
        _isLockingMode = isLockingMode;
        _chainId = chainId;
        _evmChainId = evmChainId;
    }

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function quoteDeliveryPrice(
        uint16 recipientChain
    ) public view virtual returns (uint256);

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function sendMessage(
        uint16 recipientChain,
        bytes memory payload
    ) internal virtual;

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function setSibling(
        uint16 siblingChainId,
        bytes32 siblingContract
    ) external virtual;

    /// @notice Called by the user to send the token cross-chain.
    ///         This function will either lock or burn the sender's tokens.
    ///         Finally, this function will call into the Endpoint contracts to send a message with the incrementing sequence number, msgType = 1y, and the token transfer payload.
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) external payable nonReentrant returns (uint64 msgSequence) {
        // check up front that msg.value will cover the delivery price
        uint256 totalPriceQuote = quoteDeliveryPrice(recipientChain);
        if (msg.value < totalPriceQuote) {
            revert DeliveryPaymentTooLow(totalPriceQuote, msg.value);
        }

        // refund user extra excess value from msg.value
        uint256 excessValue = totalPriceQuote - msg.value;
        if (excessValue > 0) {
            payable(msg.sender).transfer(excessValue);
        }

        // query tokens decimals
        (, bytes memory queriedDecimals) = _token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // don't deposit dust that can not be bridged due to the decimal shift
        amount = deNormalizeAmount(normalizeAmount(amount, decimals), decimals);

        if (_isLockingMode) {
            // use transferFrom to pull tokens from the user and lock them
            // query own token balance before transfer
            uint256 balanceBefore = getTokenBalanceOf(_token, address(this));

            // transfer tokens
            SafeERC20.safeTransferFrom(
                IERC20(_token),
                msg.sender,
                address(this),
                amount
            );

            // query own token balance after transfer
            uint256 balanceAfter = getTokenBalanceOf(_token, address(this));

            // correct amount for potential transfer fees
            amount = balanceAfter - balanceBefore;
        } else {
            // query sender's token balance before transfer
            uint256 balanceBefore = getTokenBalanceOf(_token, msg.sender);

            // call the token's burn function to burn the sender's token
            ERC20Burnable(_token).burnFrom(msg.sender, amount);

            // query sender's token balance after transfer
            uint256 balanceAfter = getTokenBalanceOf(_token, msg.sender);

            // correct amount for potential burn fees
            amount = balanceAfter - balanceBefore;
        }

        // normalize amount decimals
        uint256 normalizedAmount = normalizeAmount(amount, decimals);

        bytes memory encodedTransferPayload = encodeNativeTokenTransfer(
            normalizedAmount,
            _token,
            recipient,
            recipientChain
        );

        // construct the ManagerMessage payload
        _sequence = useSequence();
        bytes memory encodedManagerPayload = encodeEndpointManagerMessage(
            _chainId,
            _sequence,
            1,
            encodedTransferPayload
        );

        // send the message
        sendMessage(recipientChain, encodedManagerPayload);

        // return the sequence number
        return _sequence;
    }

    function normalizeAmount(
        uint256 amount,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (decimals > 8) {
            amount /= 10 ** (decimals - 8);
        }
        return amount;
    }

    function deNormalizeAmount(
        uint256 amount,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (decimals > 8) {
            amount *= 10 ** (decimals - 8);
        }
        return amount;
    }

    /// @dev Called by a Endpoint contract to deliver a verified attestation.
    ///      This function will decode the payload as an EndpointManagerMessage to extract the sequence, msgType, and other parameters.
    ///      When the threshold is reached for a sequence, this function will execute logic to handle the action specified by the msgType and payload.
    function _attestationReceived(bytes memory payload) internal {
        // verify chain has not forked
        checkFork(_evmChainId);

        // parse the payload as an EndpointManagerMessage
        EndpointManagerMessage memory message = parseEndpointManagerMessage(
            payload
        );

        // for msgType == 1, parse the payload as a NativeTokenTransfer.
        // for other msgTypes, revert (unsupported for now)
        if (message.msgType != 1) {
            revert UnexpectedEndpointManagerMessageType(message.msgType);
        }
        NativeTokenTransfer
            memory nativeTokenTransfer = parseNativeTokenTransfer(
                message.payload
            );

        // verify that the destination chain is valid
        if (nativeTokenTransfer.toChain != _chainId) {
            revert InvalidTargetChain(nativeTokenTransfer.toChain, _chainId);
        }

        // calculate proper amount of tokens to unlock/mint to recipient
        // query the decimals of the token contract that's tied to this manager
        // adjust the decimals of the amount in the nativeTokenTransfer payload accordingly
        (, bytes memory queriedDecimals) = _token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        uint256 nativeTransferAmount = deNormalizeAmount(
            nativeTokenTransfer.amount,
            decimals
        );

        address transferRecipient = fromWormholeFormat(nativeTokenTransfer.to);

        if (_isLockingMode) {
            // unlock tokens to the specified recipient
            SafeERC20.safeTransfer(
                IERC20(_token),
                transferRecipient,
                nativeTransferAmount
            );
        } else {
            // mint tokens to the specified recipient
            IEndpointToken(_token).mint(
                transferRecipient,
                nativeTransferAmount
            );
        }
    }

    function nextSequence() public view returns (uint64) {
        return _sequence;
    }

    function useSequence() internal returns (uint64 currentSequence) {
        currentSequence = nextSequence();
        incrementSequence();
    }

    function incrementSequence() internal {
        _sequence++;
    }

    function encodeEndpointManagerMessage(
        uint16 chainId,
        uint64 sequence,
        uint8 msgType,
        bytes memory payload
    ) public pure returns (bytes memory encoded) {
        // TODO -- should we check payload length here?
        // for example, CCTP integration checks payload is <= max(uint16)
        return abi.encodePacked(chainId, sequence, msgType, payload);
    }

    /*
     * @dev Parse a EndpointManagerMessage.
     *
     * @params encoded The byte array corresponding to the encoded message
     */
    function parseEndpointManagerMessage(
        bytes memory encoded
    ) public pure returns (EndpointManagerMessage memory managerMessage) {
        uint256 offset = 0;
        (managerMessage.chainId, offset) = encoded.asUint16(offset);
        (managerMessage.sequence, offset) = encoded.asUint64(offset);
        (managerMessage.msgType, offset) = encoded.asUint8(offset);
        (managerMessage.payload, offset) = encoded.slice(
            offset,
            encoded.length - offset
        );
    }

    function encodeNativeTokenTransfer(
        uint256 amount,
        address tokenAddr,
        bytes32 recipient,
        uint16 toChain
    ) public pure returns (bytes memory encoded) {
        return
            abi.encodePacked(
                amount,
                toWormholeFormat(tokenAddr),
                recipient,
                toChain
            );
    }

    /*
     * @dev Parse a NativeTokenTransfer.
     *
     * @params encoded The byte array corresponding to the encoded message
     */
    function parseNativeTokenTransfer(
        bytes memory encoded
    ) public pure returns (NativeTokenTransfer memory nativeTokenTransfer) {
        uint256 offset = 0;
        (nativeTokenTransfer.amount, offset) = encoded.asUint256(offset);
        (nativeTokenTransfer.tokenAddress, offset) = encoded.asBytes32(offset);
        (nativeTokenTransfer.to, offset) = encoded.asBytes32(offset);
        (nativeTokenTransfer.toChain, offset) = encoded.asUint16(offset);
    }

    function getTokenBalanceOf(
        address tokenAddr,
        address accountAddr
    ) internal view returns (uint256) {
        (, bytes memory queriedBalance) = tokenAddr.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, accountAddr)
        );
        return abi.decode(queriedBalance, (uint256));
    }
}

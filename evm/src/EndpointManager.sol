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

abstract contract EndpointManager is IEndpointManager, OwnableUpgradeable, ReentrancyGuard {
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;

    enum Mode {
        LOCKING,
        BURNING
    }

    address immutable _token;
    Mode immutable _mode;
    uint16 immutable _chainId;
    uint256 immutable _evmChainId;

    uint64 _sequence;

    constructor(address token, Mode mode, uint16 chainId) {
        _token = token;
        _mode = mode;
        _chainId = chainId;
        _evmChainId = block.chainid;
    }

    function initialize() public initializer {
        // TODO: shouldn't be msg.sender but a separate (contract) address that's passed in the initializer
        __Ownable_init(msg.sender);
    }

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function quoteDeliveryPrice(uint16 recipientChain) public view virtual returns (uint256);

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function sendMessage(uint16 recipientChain, bytes memory payload) internal virtual;

    /// @dev This will either cross-call or internal call, depending on whether the contract is standalone or not.
    function setSibling(uint16 siblingChainId, bytes32 siblingContract) external virtual;

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
        (, bytes memory queriedDecimals) = _token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // don't deposit dust that can not be bridged due to the decimal shift
        amount = deNormalizeAmount(normalizeAmount(amount, decimals), decimals);

        if (amount == 0) {
            revert ZeroAmount();
        }

        if (_mode == Mode.LOCKING) {
            // use transferFrom to pull tokens from the user and lock them
            // query own token balance before transfer
            uint256 balanceBefore = getTokenBalanceOf(_token, address(this));

            // transfer tokens
            IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);

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

        NativeTokenTransfer memory nativeTokenTransfer =
            NativeTokenTransfer({amount: normalizedAmount, to: recipient, toChain: recipientChain});

        bytes memory encodedTransferPayload = encodeNativeTokenTransfer(nativeTokenTransfer);

        // construct the ManagerMessage payload
        _sequence = useSequence();
        bytes memory encodedManagerPayload = encodeEndpointManagerMessage(
            EndpointManagerMessage(_chainId, _sequence, 1, encodedTransferPayload)
        );

        // send the message
        sendMessage(recipientChain, encodedManagerPayload);

        // return the sequence number
        return _sequence;
    }

    function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals > 8) {
            amount /= 10 ** (decimals - 8);
        }
        return amount;
    }

    function deNormalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals > 8) {
            amount *= 10 ** (decimals - 8);
        }
        return amount;
    }

    /// @dev Called after a message has been sufficiently verified to execute the command in the message.
    ///      This function will decode the payload as an EndpointManagerMessage to extract the sequence, msgType, and other parameters.
    function _executeMsg(bytes memory payload) internal {
        // verify chain has not forked
        checkFork(_evmChainId);

        // parse the payload as an EndpointManagerMessage
        EndpointManagerMessage memory message = parseEndpointManagerMessage(payload);

        // for msgType == 1, parse the payload as a NativeTokenTransfer.
        // for other msgTypes, revert (unsupported for now)
        if (message.msgType != 1) {
            revert UnexpectedEndpointManagerMessageType(message.msgType);
        }
        NativeTokenTransfer memory nativeTokenTransfer = parseNativeTokenTransfer(message.payload);

        // verify that the destination chain is valid
        if (nativeTokenTransfer.toChain != _chainId) {
            revert InvalidTargetChain(nativeTokenTransfer.toChain, _chainId);
        }

        // calculate proper amount of tokens to unlock/mint to recipient
        // query the decimals of the token contract that's tied to this manager
        // adjust the decimals of the amount in the nativeTokenTransfer payload accordingly
        (, bytes memory queriedDecimals) = _token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        uint256 nativeTransferAmount = deNormalizeAmount(nativeTokenTransfer.amount, decimals);

        address transferRecipient = fromWormholeFormat(nativeTokenTransfer.to);

        if (_mode == Mode.LOCKING) {
            // unlock tokens to the specified recipient
            IERC20(_token).safeTransfer(transferRecipient, nativeTransferAmount);
        } else {
            // mint tokens to the specified recipient
            IEndpointToken(_token).mint(transferRecipient, nativeTransferAmount);
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

    function encodeEndpointManagerMessage(EndpointManagerMessage memory m)
        public
        pure
        returns (bytes memory encoded)
    {
        uint16 payloadLength = uint16(m.payload.length);
        return abi.encodePacked(m.chainId, m.sequence, m.msgType, payloadLength, m.payload);
    }

    /*
     * @dev Parse a EndpointManagerMessage.
     *
     * @params encoded The byte array corresponding to the encoded message
     */
    function parseEndpointManagerMessage(bytes memory encoded)
        public
        pure
        returns (EndpointManagerMessage memory managerMessage)
    {
        uint256 offset = 0;
        (managerMessage.chainId, offset) = encoded.asUint16Unchecked(offset);
        (managerMessage.sequence, offset) = encoded.asUint64Unchecked(offset);
        (managerMessage.msgType, offset) = encoded.asUint8Unchecked(offset);
        uint256 payloadLength;
        (payloadLength, offset) = encoded.asUint16Unchecked(offset);
        (managerMessage.payload, offset) = encoded.sliceUnchecked(offset, payloadLength);
        encoded.checkLength(offset);
    }

    function encodeNativeTokenTransfer(NativeTokenTransfer memory m)
        public
        pure
        returns (bytes memory encoded)
    {
        return abi.encodePacked(m.amount, m.to, m.toChain);
    }

    /*
     * @dev Parse a NativeTokenTransfer.
     *
     * @params encoded The byte array corresponding to the encoded message
     */
    function parseNativeTokenTransfer(bytes memory encoded)
        public
        pure
        returns (NativeTokenTransfer memory nativeTokenTransfer)
    {
        uint256 offset = 0;
        (nativeTokenTransfer.amount, offset) = encoded.asUint256(offset);
        (nativeTokenTransfer.to, offset) = encoded.asBytes32(offset);
        (nativeTokenTransfer.toChain, offset) = encoded.asUint16(offset);
        encoded.checkLength(offset);
    }

    function getTokenBalanceOf(
        address tokenAddr,
        address accountAddr
    ) internal view returns (uint256) {
        (, bytes memory queriedBalance) =
            tokenAddr.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, accountAddr));
        return abi.decode(queriedBalance, (uint256));
    }

    function token() external view override returns (address) {
        return _token;
    }
}

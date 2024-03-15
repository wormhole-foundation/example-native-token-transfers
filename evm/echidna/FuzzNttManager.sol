pragma solidity >=0.8.8 <0.9.0;

import "../src/NttManager/NttManager.sol";
import "../src/mocks/DummyToken.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/interfaces/IManagerBase.sol";
import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IRateLimiter.sol";
import "../src/libraries/external/OwnableUpgradeable.sol";
import "./helpers/FuzzingHelpers.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../test/mocks/DummyTransceiver.sol";

contract FuzzNttManager is FuzzingHelpers {


    NttManager nttManager;
    DummyToken dummyToken;
    DummyTransceiver dummyTransceiver;

    constructor() {
        _initialManagerSetup();
        
        dummyToken.mintDummy(address(this), type(uint256).max);
        IERC20(dummyToken).approve(address(nttManager), type(uint256).max);
    }

    function transfer(uint256 amount, uint16 recipientChainId, bytes32 recipient, bytes32 peerContract, uint8 peerDecimals, uint256 inboundLimit, bool shouldQueue) public {
        require(peerContract != bytes32(0));
        
        uint8 decimals = ERC20(dummyToken).decimals();
        uint8 minDecimals =  minUint8(8, minUint8(decimals, peerDecimals));

        amount = clampBetween(amount, 10 ** (decimals - minDecimals), type(uint64).max * 10 ** (decimals - minUint8(8, decimals)));
        amount = TrimmedAmountLib.scale(amount, decimals, minDecimals);
        amount = TrimmedAmountLib.scale(amount, minDecimals, decimals);

        // Make sure the peer is set to a valid config
        peerDecimals = uint8(clampBetween(peerDecimals, 1, type(uint8).max));
        recipientChainId = uint16(clampBetween(recipientChainId, 1, type(uint16).max));
        setPeer(recipientChainId, peerContract, peerDecimals, inboundLimit, true);

        uint256 nttManagerBalanceBefore = IERC20(dummyToken).balanceOf(address(nttManager));
        uint256 thisAddressBalanceBefore = IERC20(dummyToken).balanceOf(address(nttManager));

        uint256 currentOutboundCapacity = nttManager.getCurrentOutboundCapacity();
        uint64 nextMessageSequence = nttManager.nextMessageSequence();

        try nttManager.transfer(amount, recipientChainId, recipient, shouldQueue, new bytes(1)) {
            assert(IERC20(dummyToken).balanceOf(address(this)) == thisAddressBalanceBefore - amount);
            assert(IERC20(dummyToken).balanceOf(address(nttManager)) == amount + nttManagerBalanceBefore);

            // If we queued, we should have an item in the queue
            if ((shouldQueue && amount > currentOutboundCapacity)) {
                IRateLimiter.OutboundQueuedTransfer memory queuedTransfer = nttManager.getOutboundQueuedTransfer(nextMessageSequence);
                assert(
                    queuedTransfer.txTimestamp == block.timestamp &&
                    queuedTransfer.recipient == recipient &&
                    TrimmedAmountLib.getAmount(queuedTransfer.amount) == TrimmedAmountLib.scale(amount, decimals, minDecimals) &&
                    TrimmedAmountLib.getDecimals(queuedTransfer.amount) == minDecimals &&
                    queuedTransfer.recipientChain == recipientChainId &&
                    queuedTransfer.sender == address(this) &&
                    queuedTransfer.transceiverInstructions == bytes(1)
                );
            }
        }
        catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            if (amount == 0) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.ZeroAmount.selector),
                    "NttManager: transfer expected to fail if sending with 0 amount"
                );
            }
            else if (recipient == bytes32(0)) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.InvalidRecipient.selector),
                    "NttManager: transfer expected to fail if sending to 0 address"
                );
            }
            else if (peerDecimals == 0) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.InvalidPeerDecimals.selector),
                    "NttManager: transfer expected to fail if sending to a peer with 0 decimals"
                );
            }
            else if (!shouldQueue && amount > currentOutboundCapacity) {
                assertWithMsg(
                    errorSelector == selectorToUint(IRateLimiter.NotEnoughCapacity.selector),
                    "NttManager: transfer expected to fail if exceeding rate limit and not queueing"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: transfer unexpected revert"
                );
            }
        }
    }

    function setPeer(uint16 peerChainId,
        bytes32 peerContract,
        uint8 decimals,
        uint256 inboundLimit,
        bool clampLimit
    ) public {
        uint8 localDecimals = ERC20(dummyToken).decimals();
        if (clampLimit) inboundLimit = clampBetween(inboundLimit, 0, type(uint64).max * 10 ** (localDecimals - minUint8(8, localDecimals)));

        try nttManager.setPeer(peerChainId, peerContract, decimals, inboundLimit) {

        }
        catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);
            
            if (peerChainId == 0) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.InvalidPeerChainIdZero.selector),
                    "NttManager: setPeer expected to fail if setting zero peer chain id"
                );
            }
            else if (peerContract == bytes32(0)) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.InvalidPeerZeroAddress.selector),
                    "NttManager: setPeer expected to fail if setting zero peer contract address"
                );
            }
            else if (decimals == 0) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.InvalidPeerDecimals.selector),
                    "NttManager: setPeer expected to fail if setting zero peer decimals"
                );
            }
            else if (!clampLimit) {
                bytes32 errorStringHash = extractErrorString(revertData);
                assertWithMsg(
                    errorStringHash == keccak256(abi.encodePacked("SafeCast: value doesn't fit in 64 bits")),
                    "NttManager: setPeer expected to fail if setting too large an inbound limit"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: setPeer unexpected revert"
                );
            }
        }
    }

    function setOutboundLimit(uint256 limit, bool clampLimit) public {
        uint8 localDecimals = ERC20(dummyToken).decimals();
        if (clampLimit) limit = clampBetween(limit, 0, type(uint64).max * 10 ** (localDecimals - minUint8(8, localDecimals)));
        
        try nttManager.setOutboundLimit(limit) {

        }
        catch (bytes memory revertData) {
            if (!clampLimit) {
                bytes32 errorStringHash = extractErrorString(revertData);
                assertWithMsg(
                    errorStringHash == keccak256(abi.encodePacked("SafeCast: value doesn't fit in 64 bits")),
                    "NttManager: setOutboundLimit expected to fail if setting too large a limit"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: setOutboundLimit unexpected revert"
                );
            }
        }
    }

    function setInboundLimit(uint256 limit, uint16 chainId, bool clampLimit) public {
        uint8 localDecimals = ERC20(dummyToken).decimals();
        if (clampLimit) limit = clampBetween(limit, 0, type(uint64).max * 10 ** (localDecimals - minUint8(8, localDecimals)));
        
        try nttManager.setInboundLimit(limit, chainId) {

        }
        catch (bytes memory revertData) {
            if (!clampLimit) {
                bytes32 errorStringHash = extractErrorString(revertData);
                assertWithMsg(
                    errorStringHash == keccak256(abi.encodePacked("SafeCast: value doesn't fit in 64 bits")),
                    "NttManager: setInboundLimit expected to fail if setting too large a limit"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: setInboundLimit unexpected revert"
                );
            }
        }
    }

    /// INTERNAL METHODS

    function _initialManagerSetup() internal {
        // Deploy an NTT token
        dummyToken = new DummyToken();
        // Deploy an implementation of the manager
        NttManager implementation = new NttManager(address(dummyToken), IManagerBase.Mode.LOCKING, 1, 1 days, false);
        // Place the manager behind a proxy
        nttManager = NttManager(address(new ERC1967Proxy(address(implementation), "")));
        // Initialize the proxy
        nttManager.initialize();



        // Set a transceiver since we need at least 1
        dummyTransceiver = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(dummyTransceiver));
    }
}
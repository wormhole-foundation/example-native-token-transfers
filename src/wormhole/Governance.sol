// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

contract Governance {
    using BytesParsing for bytes;

    // "GeneralPurposeGovernance" (left padded)
    bytes32 public constant MODULE =
        0x000000000000000047656E6572616C507572706F7365476F7665726E616E6365;

    enum GovernanceAction {
        UNDEFINED,
        EVM_CALL
    }

    IWormhole immutable wormhole;

    error PayloadTooLong(uint256 size);
    error InvalidModule(bytes32 module);
    error InvalidAction(uint8 action);
    error InvalidGovernanceChainId(uint16 chainId);
    error InvalidGovernanceContract(bytes32 contractAddress);
    error GovernanceActionAlreadyConsumed(bytes32 digest);

    error NotRecipientChain(uint16 chainId);
    error NotRecipientContract(address contractAddress);

    bytes32 constant CONSUMED_GOVERNANCE_ACTIONS_SLOT =
        bytes32(uint256(keccak256("governance.consumedGovernanceActions")) - 1);

    function _getConsumedGovernanceActionsStorage()
        private
        pure
        returns (mapping(bytes32 => bool) storage $)
    {
        uint256 slot = uint256(CONSUMED_GOVERNANCE_ACTIONS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    /*
    * @dev General purpose governance message to call arbitrary methods on a governed smart contract.
    *      This message adheres to the Wormhole governance packet standard: https://github.com/wormhole-foundation/wormhole/blob/main/whitepapers/0002_governance_messaging.md
    *      The wire format for this message is:
    *      - module - 32 bytes
    *      - action - 1 byte
    *      - chain - 2 bytes
    *      - governanceContract - 20 bytes
    *      - governedContract - 20 bytes
    *      - callDataLength - 2 bytes
    *      - callData - `callDataLength` bytes
    */
    struct GeneralPurposeGovernanceMessage {
        bytes32 module;
        uint8 action;
        uint16 chain;
        address governanceContract;
        address governedContract;
        bytes callData;
    }

    constructor(address _wormhole) {
        wormhole = IWormhole(_wormhole);
    }

    function performGovernance(bytes calldata vaa) external {
        IWormhole.VM memory verified = _verifyGovernanceVAA(vaa);
        GeneralPurposeGovernanceMessage memory message =
            parseGeneralPurposeGovernanceMessage(verified.payload);

        if (message.module != MODULE) {
            revert InvalidModule(message.module);
        }

        if (message.action != uint8(GovernanceAction.EVM_CALL)) {
            revert InvalidAction(message.action);
        }

        if (message.chain != wormhole.chainId()) {
            revert NotRecipientChain(message.chain);
        }

        if (message.governanceContract != address(this)) {
            revert NotRecipientContract(message.governanceContract);
        }

        // TODO: any other checks? the call is trusted (signed by guardians),
        // but what's the worst that could happen to this contract?
        (bool success, bytes memory returnData) = message.governedContract.call(message.callData);
        if (!success) {
            revert(string(returnData));
        }
    }

    function _replayProtect(bytes32 digest) internal {
        mapping(bytes32 => bool) storage $ = _getConsumedGovernanceActionsStorage();
        if ($[digest]) {
            revert GovernanceActionAlreadyConsumed(digest);
        }
        $[digest] = true;
    }

    function _verifyGovernanceVAA(bytes memory encodedVM)
        internal
        returns (IWormhole.VM memory parsedVM)
    {
        (IWormhole.VM memory vm, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(encodedVM);

        if (!valid) {
            revert(reason);
        }

        if (vm.emitterChainId != wormhole.governanceChainId()) {
            revert InvalidGovernanceChainId(vm.emitterChainId);
        }

        if (vm.emitterAddress != wormhole.governanceContract()) {
            revert InvalidGovernanceContract(vm.emitterAddress);
        }

        _replayProtect(vm.hash);

        return vm;
    }

    function encodeGeneralPurposeGovernanceMessage(GeneralPurposeGovernanceMessage memory m)
        public
        pure
        returns (bytes memory encoded)
    {
        if (m.callData.length > type(uint16).max) {
            revert PayloadTooLong(m.callData.length);
        }
        uint16 callDataLength = uint16(m.callData.length);
        return abi.encodePacked(
            m.module,
            m.action,
            m.chain,
            m.governanceContract,
            m.governedContract,
            callDataLength,
            m.callData
        );
    }

    function parseGeneralPurposeGovernanceMessage(bytes memory encoded)
        public
        pure
        returns (GeneralPurposeGovernanceMessage memory message)
    {
        uint256 offset = 0;
        (message.module, offset) = encoded.asBytes32Unchecked(offset);
        (message.action, offset) = encoded.asUint8Unchecked(offset);
        (message.chain, offset) = encoded.asUint16Unchecked(offset);
        (message.governanceContract, offset) = encoded.asAddressUnchecked(offset);
        (message.governedContract, offset) = encoded.asAddressUnchecked(offset);
        uint256 callDataLength;
        (callDataLength, offset) = encoded.asUint16Unchecked(offset);
        (message.callData, offset) = encoded.sliceUnchecked(offset, callDataLength);
        encoded.checkLength(offset);
    }
}

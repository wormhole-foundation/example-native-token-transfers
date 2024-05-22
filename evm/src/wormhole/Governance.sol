// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

contract Governance {
    using BytesParsing for bytes;

    // Only 2 Guardian signatures are required for quorum to call the pause function on governed contracts.
    uint PAUSER_QUORUM = 2;

    // "GeneralPurposeGovernance" (left padded)
    bytes32 public constant MODULE =
        0x000000000000000047656E6572616C507572706F7365476F7665726E616E6365;

    /// @notice The known set of governance actions.
    /// @dev As the governance logic is expanded to more runtimes, it's
    ///      important to keep them in sync, at least the newer ones should ensure
    ///      they don't overlap with the existing ones.
    ///
    ///      Existing implementations are not strongly required to be updated
    ///      to be aware of new actions (as they will never need to know the
    ///      action indices higher than the one corresponding to the current
    ///      runtime), but it's good practice.
    ///
    ///      When adding a new runtime, make sure to at least update in the README.md
    enum GovernanceAction {
        UNDEFINED,
        EVM_CALL,
        SOLANA_CALL
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
    *      - MODULE - 32 bytes
    *      - action - 1 byte
    *      - chain - 2 bytes
    *      - governanceContract - 20 bytes
    *      - governedContract - 20 bytes
    *      - callDataLength - 2 bytes
    *      - callData - `callDataLength` bytes
    */
    struct GeneralPurposeGovernanceMessage {
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
        IWormhole.VM memory vm = wormhole.parseVM(encodedVM);
        GeneralPurposeGovernanceMessage memory message =
            parseGeneralPurposeGovernanceMessage(vm.payload);

        bytes memory pauseSig = abi.encodeWithSignature("pause()");
        if (keccak256(message.callData) == keccak256(pauseSig)) {
            // If we're calling the pause() function, only require 2 Guardian signatures
            (bool valid, string memory reason) = _verifyVMForPause(vm, true);
            if (!valid) {
                revert(reason);
            }
        } else {
            // If we're calling any other function signature, require the full 13 Guardian signatures
            (bool valid, string memory reason) = wormhole.verifyVM(vm);
            if (!valid) {
                revert(reason);
            }
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

    /**
    * @dev COPIED FROM WORMHOLE CORE CONTRACT AND RENAMED TO `verifyVMForPause` 
    * `verifyVMInternal` serves to validate an arbitrary vm against a valid Guardian set
    * if checkHash is set then the hash field of the vm is verified against the hash of its contents
    * in the case that the vm is securely parsed and the hash field can be trusted, checkHash can be set to false
    * as the check would be redundant
    */
    function _verifyVMForPause(IWormhole.VM memory vm, bool checkHash) internal view returns (bool valid, string memory reason) {
        /// @dev Obtain the current guardianSet for the guardianSetIndex provided
        IWormhole.GuardianSet memory guardianSet = wormhole.getGuardianSet(vm.guardianSetIndex);

        /**
         * Verify that the hash field in the vm matches with the hash of the contents of the vm if checkHash is set
         * WARNING: This hash check is critical to ensure that the vm.hash provided matches with the hash of the body.
         * Without this check, it would not be safe to call verifyVM on it's own as vm.hash can be a valid signed hash
         * but the body of the vm could be completely different from what was actually signed by the guardians
         */
        if(checkHash){
            bytes memory body = abi.encodePacked(
                vm.timestamp,
                vm.nonce,
                vm.emitterChainId,
                vm.emitterAddress,
                vm.sequence,
                vm.consistencyLevel,
                vm.payload
            );

            bytes32 vmHash = keccak256(abi.encodePacked(keccak256(body)));

            if(vmHash != vm.hash){
                return (false, "vm.hash doesn't match body");
            }
        }

       /**
        * @dev Checks whether the guardianSet has zero keys
        * WARNING: This keys check is critical to ensure the guardianSet has keys present AND to ensure
        * that guardianSet key size doesn't fall to zero and negatively impact quorum assessment.  If guardianSet
        * key length is 0 and vm.signatures length is 0, this could compromise the integrity of both vm and
        * signature verification.
        */
        if(guardianSet.keys.length == 0){
            return (false, "invalid guardian set");
        }

        /// @dev Checks if VM guardian set index matches the current index (unless the current set is expired).
        if(vm.guardianSetIndex != wormhole.getCurrentGuardianSetIndex() && guardianSet.expirationTime < block.timestamp){
            return (false, "guardian set has expired");
        }

       /**
        * @dev We're using a fixed point number transformation with 1 decimal to deal with rounding.
        *   WARNING: This quorum check is critical to assessing whether we have enough Guardian signatures to validate a VM
        *   if making any changes to this, obtain additional peer review. If guardianSet key length is 0 and
        *   vm.signatures length is 0, this could compromise the integrity of both vm and signature verification.
        */
        uint fullQuorum = wormhole.quorum(guardianSet.keys.length);
        uint requiredPauseQuorum = PAUSER_QUORUM < fullQuorum ? PAUSER_QUORUM : fullQuorum;
        if (vm.signatures.length < requiredPauseQuorum){
            return (false, "no quorum");
        }

        /// @dev Verify the proposed vm.signatures against the guardianSet
        (bool signaturesValid, string memory invalidReason) = wormhole.verifySignatures(vm.hash, vm.signatures, guardianSet);
        if(!signaturesValid){
            return (false, invalidReason);
        }

        /// If we are here, we've validated the VM is a valid multi-sig that matches the guardianSet.
        return (true, "");
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
            MODULE,
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

        bytes32 module;
        (module, offset) = encoded.asBytes32Unchecked(offset);
        if (module != MODULE) {
            revert InvalidModule(module);
        }

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

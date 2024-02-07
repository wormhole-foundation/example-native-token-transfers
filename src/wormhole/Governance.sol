// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/interfaces/IWormhole.sol";

contract Governance {
    IWormhole immutable wormhole;

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

    struct GovernanceMessage {
        uint16 chainId;
        address governanceContract;
        address governedContract;
        bytes callData;
    }

    constructor(address _wormhole) {
        wormhole = IWormhole(_wormhole);
    }

    function performGovernance(bytes calldata vaa) external {
        IWormhole.VM memory verified = _verifyGovernanceVAA(vaa);
        GovernanceMessage memory message = abi.decode(verified.payload, (GovernanceMessage));

        if (message.chainId != wormhole.chainId()) {
            revert NotRecipientChain(message.chainId);
        }
        if (message.governanceContract != address(this)) {
            revert NotRecipientContract(message.governanceContract);
        }
        bytes memory callData = message.callData;

        // TODO: any other checks? the call is trusted (signed by guardians),
        // but what's the worst that could happen to this contract?
        (bool success, bytes memory returnData) = message.governedContract.call(callData);
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
}

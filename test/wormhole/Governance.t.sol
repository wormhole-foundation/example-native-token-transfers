// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import "../../src/wormhole/Governance.sol";
import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";

contract GovernedContract is Ownable {
    bool public governanceStuffCalled;

    function governanceStuff() public onlyOwner {
        governanceStuffCalled = true;
    }
}

contract GovernanceTest is Test {
    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;

    Governance governance;
    WormholeSimulator guardian;
    GovernedContract myContract;
    IWormhole constant wormhole = IWormhole(0x706abc4E45D419950511e474C7B9Ed348A4a716c);

    function setUp() public {
        string memory url = "https://ethereum-goerli.publicnode.com";
        vm.createSelectFork(url);

        guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);
        governance = new Governance(address(wormhole));

        myContract = new GovernedContract();
        myContract.transferOwnership(address(governance));
    }

    function test_governance() public {
        uint16 thisChain = wormhole.chainId();

        Governance.GovernanceMessage memory message = Governance.GovernanceMessage({
            chainId: thisChain,
            governanceContract: address(governance),
            governedContract: address(myContract),
            callData: abi.encodeWithSignature("governanceStuff()")
        });

        IWormhole.VM memory vaa = IWormhole.VM({
            version: 1,
            timestamp: uint32(block.timestamp),
            nonce: 0,
            emitterChainId: wormhole.governanceChainId(),
            emitterAddress: wormhole.governanceContract(),
            sequence: 0,
            consistencyLevel: 200,
            payload: abi.encode(message),
            guardianSetIndex: 0,
            signatures: new IWormhole.Signature[](0),
            hash: bytes32("")
        });

        bytes memory signed = guardian.encodeAndSignMessage(vaa);

        governance.performGovernance(signed);

        assert(myContract.governanceStuffCalled());
    }

    function test_transferOwnership() public {
        address newOwner = address(0x1234);
        uint16 thisChain = wormhole.chainId();

        Governance.GovernanceMessage memory message = Governance.GovernanceMessage({
            chainId: thisChain,
            governanceContract: address(governance),
            governedContract: address(myContract),
            callData: abi.encodeWithSignature("transferOwnership(address)", newOwner)
        });

        IWormhole.VM memory vaa = IWormhole.VM({
            version: 1,
            timestamp: uint32(block.timestamp),
            nonce: 0,
            emitterChainId: wormhole.governanceChainId(),
            emitterAddress: wormhole.governanceContract(),
            sequence: 0,
            consistencyLevel: 200,
            payload: abi.encode(message),
            guardianSetIndex: 0,
            signatures: new IWormhole.Signature[](0),
            hash: bytes32("")
        });

        bytes memory signed = guardian.encodeAndSignMessage(vaa);

        governance.performGovernance(signed);

        vm.prank(newOwner);
        myContract.governanceStuff();

        assert(myContract.governanceStuffCalled());
    }

    // TODO: tests triggering the error conditions
}

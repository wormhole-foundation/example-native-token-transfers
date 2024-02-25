/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { Governance, GovernanceInterface } from "../Governance";

const _abi = [
  {
    type: "constructor",
    inputs: [
      {
        name: "_wormhole",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "MODULE",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "encodeGeneralPurposeGovernanceMessage",
    inputs: [
      {
        name: "m",
        type: "tuple",
        internalType: "struct Governance.GeneralPurposeGovernanceMessage",
        components: [
          {
            name: "action",
            type: "uint8",
            internalType: "uint8",
          },
          {
            name: "chain",
            type: "uint16",
            internalType: "uint16",
          },
          {
            name: "governanceContract",
            type: "address",
            internalType: "address",
          },
          {
            name: "governedContract",
            type: "address",
            internalType: "address",
          },
          {
            name: "callData",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "encoded",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "parseGeneralPurposeGovernanceMessage",
    inputs: [
      {
        name: "encoded",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [
      {
        name: "message",
        type: "tuple",
        internalType: "struct Governance.GeneralPurposeGovernanceMessage",
        components: [
          {
            name: "action",
            type: "uint8",
            internalType: "uint8",
          },
          {
            name: "chain",
            type: "uint16",
            internalType: "uint16",
          },
          {
            name: "governanceContract",
            type: "address",
            internalType: "address",
          },
          {
            name: "governedContract",
            type: "address",
            internalType: "address",
          },
          {
            name: "callData",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "performGovernance",
    inputs: [
      {
        name: "vaa",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "error",
    name: "GovernanceActionAlreadyConsumed",
    inputs: [
      {
        name: "digest",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
  },
  {
    type: "error",
    name: "InvalidAction",
    inputs: [
      {
        name: "action",
        type: "uint8",
        internalType: "uint8",
      },
    ],
  },
  {
    type: "error",
    name: "InvalidGovernanceChainId",
    inputs: [
      {
        name: "chainId",
        type: "uint16",
        internalType: "uint16",
      },
    ],
  },
  {
    type: "error",
    name: "InvalidGovernanceContract",
    inputs: [
      {
        name: "contractAddress",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
  },
  {
    type: "error",
    name: "InvalidModule",
    inputs: [
      {
        name: "module",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
  },
  {
    type: "error",
    name: "LengthMismatch",
    inputs: [
      {
        name: "encodedLength",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "expectedLength",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "NotRecipientChain",
    inputs: [
      {
        name: "chainId",
        type: "uint16",
        internalType: "uint16",
      },
    ],
  },
  {
    type: "error",
    name: "NotRecipientContract",
    inputs: [
      {
        name: "contractAddress",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "OutOfBounds",
    inputs: [
      {
        name: "offset",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "length",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "PayloadTooLong",
    inputs: [
      {
        name: "size",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
] as const;

const _bytecode =
  "0x60a060405234801561001057600080fd5b506040516110f23803806110f283398101604081905261002f91610040565b6001600160a01b0316608052610070565b60006020828403121561005257600080fd5b81516001600160a01b038116811461006957600080fd5b9392505050565b6080516110526100a060003960008181610161015281816104eb015281816105a1015261065a01526110526000f3fe608060405234801561001057600080fd5b506004361061004c5760003560e01c8063094d3a34146100515780635601672414610083578063b281d07a14610098578063cfa82897146100b8575b600080fd5b6100707747656e6572616c507572706f7365476f7665726e616e636581565b6040519081526020015b60405180910390f35b6100966100913660046108db565b6100d8565b005b6100ab6100a6366004610a82565b6102e7565b60405161007a9190610b0f565b6100cb6100c6366004610ba5565b6103f7565b60405161007a9190610c5a565b600061011983838080601f01602080910402602001604051908101604052809392919081815260200183838082843760009201919091525061048c92505050565b9050600061012a8260e001516102e7565b805190915060ff1660011461015f5780516040516317949c6760e11b815260ff90911660048201526024015b60405180910390fd5b7f00000000000000000000000000000000000000000000000000000000000000006001600160a01b0316639a8a05926040518163ffffffff1660e01b8152600401602060405180830381865afa1580156101bd573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101e19190610c7f565b61ffff16816020015161ffff1614610218576020810151604051638510fea560e01b815261ffff9091166004820152602401610156565b60408101516001600160a01b03163014610256576040808201519051630212334760e41b81526001600160a01b039091166004820152602401610156565b60008082606001516001600160a01b031683608001516040516102799190610c9c565b6000604051808303816000865af19150503d80600081146102b6576040519150601f19603f3d011682016040523d82523d6000602084013e6102bb565b606091505b5091509150816102df578060405162461bcd60e51b81526004016101569190610c5a565b505050505050565b6040805160a08101825260008082526020820181905291810182905260608082018390526080820152908061031c848261071c565b925090507747656e6572616c507572706f7365476f7665726e616e6365811461035b57604051638c1c0dbf60e01b815260048101829052602401610156565b818401600181015160ff16845260039081015161ffff166020850152909101906103858483610744565b6001600160a01b03909116604085015291506103a18483610744565b6001600160a01b039091166060850152915060006103c88584600291810182015192910190565b935061ffff1690506103db858483610754565b608086019190915292506103ef85846107c9565b505050919050565b606061ffff8016826080015151111561042c5781608001515160405163a341969160e01b815260040161015691815260200190565b608082015180518351602080860151604080880151606089015191519596610475967747656e6572616c507572706f7365476f7665726e616e6365969592939289929101610cb8565b604051602081830303815290604052915050919050565b604080516101608101825260008082526020820181905291810182905260608082018390526080820183905260a0820183905260c0820183905260e08201819052610100820183905261012082015261014081019190915260008060007f00000000000000000000000000000000000000000000000000000000000000006001600160a01b031663c0fd8bde866040518263ffffffff1660e01b81526004016105359190610c5a565b600060405180830381865afa158015610552573d6000803e3d6000fd5b505050506040513d6000823e601f3d908101601f1916820160405261057a9190810190610e8a565b9250925092508161059f578060405162461bcd60e51b81526004016101569190610c5a565b7f00000000000000000000000000000000000000000000000000000000000000006001600160a01b031663fbe3c2cd6040518163ffffffff1660e01b8152600401602060405180830381865afa1580156105fd573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906106219190610c7f565b61ffff16836060015161ffff161461065857606083015160405163259b974160e11b815261ffff9091166004820152602401610156565b7f00000000000000000000000000000000000000000000000000000000000000006001600160a01b031663b172b2226040518163ffffffff1660e01b8152600401602060405180830381865afa1580156106b6573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906106da9190610fe2565b83608001511461070557826080015160405163dd16ea0760e01b815260040161015691815260200190565b6107138361014001516107fb565b50909392505050565b6000806000806107358686602091810182015192910190565b909450925050505b9250929050565b6000806000806107358686610854565b6060600082600003610777575050604080516000815260208101909152826107c1565b5050604051828201601f83168061078c575060205b80830184810186838901015b818310156107b0578051835260209283019201610798565b5050848452601f01601f1916604052505b935093915050565b808251146107f75781516040516355c5b3e360e11b8152600481019190915260248101829052604401610156565b5050565b600061080561087c565b60008381526020829052604090205490915060ff161561083b576040516364cbf47160e01b815260048101839052602401610156565b600091825260205260409020805460ff19166001179055565b60008061086a8484601491810182015192910190565b8551919350915061073d9082906108b0565b6000806108aa60017f70eabfd7aa6e31808f975131c5b8c69fc72fba8ff2ad97ffb1c2acba4582aaee610ffb565b92915050565b808211156107f757604051633d71388b60e21b81526004810183905260248101829052604401610156565b600080602083850312156108ee57600080fd5b823567ffffffffffffffff8082111561090657600080fd5b818501915085601f83011261091a57600080fd5b81358181111561092957600080fd5b86602082850101111561093b57600080fd5b60209290920196919550909350505050565b634e487b7160e01b600052604160045260246000fd5b60405160a0810167ffffffffffffffff811182821017156109865761098661094d565b60405290565b6040516080810167ffffffffffffffff811182821017156109865761098661094d565b604051610160810167ffffffffffffffff811182821017156109865761098661094d565b604051601f8201601f1916810167ffffffffffffffff811182821017156109fc576109fc61094d565b604052919050565b600067ffffffffffffffff821115610a1e57610a1e61094d565b50601f01601f191660200190565b600082601f830112610a3d57600080fd5b8135610a50610a4b82610a04565b6109d3565b818152846020838601011115610a6557600080fd5b816020850160208301376000918101602001919091529392505050565b600060208284031215610a9457600080fd5b813567ffffffffffffffff811115610aab57600080fd5b610ab784828501610a2c565b949350505050565b60005b83811015610ada578181015183820152602001610ac2565b50506000910152565b60008151808452610afb816020860160208601610abf565b601f01601f19169290920160200192915050565b6020815260ff825116602082015261ffff60208301511660408201526000604083015160018060a01b0380821660608501528060608601511660808501525050608083015160a080840152610ab760c0840182610ae3565b60ff81168114610b7657600080fd5b50565b61ffff81168114610b7657600080fd5b80356001600160a01b0381168114610ba057600080fd5b919050565b600060208284031215610bb757600080fd5b813567ffffffffffffffff80821115610bcf57600080fd5b9083019060a08286031215610be357600080fd5b610beb610963565b8235610bf681610b67565b81526020830135610c0681610b79565b6020820152610c1760408401610b89565b6040820152610c2860608401610b89565b6060820152608083013582811115610c3f57600080fd5b610c4b87828601610a2c565b60808301525095945050505050565b602081526000610c6d6020830184610ae3565b9392505050565b8051610ba081610b79565b600060208284031215610c9157600080fd5b8151610c6d81610b79565b60008251610cae818460208701610abf565b9190910192915050565b87815260ff60f81b8760f81b166020820152600061ffff60f01b808860f01b1660218401526bffffffffffffffffffffffff19808860601b166023850152808760601b16603785015250808560f01b16604b840152508251610d2181604d850160208701610abf565b91909101604d0198975050505050505050565b8051610ba081610b67565b805163ffffffff81168114610ba057600080fd5b805167ffffffffffffffff81168114610ba057600080fd5b600082601f830112610d7c57600080fd5b8151610d8a610a4b82610a04565b818152846020838601011115610d9f57600080fd5b610ab7826020830160208701610abf565b600082601f830112610dc157600080fd5b8151602067ffffffffffffffff821115610ddd57610ddd61094d565b610deb818360051b016109d3565b82815260079290921b84018101918181019086841115610e0a57600080fd5b8286015b84811015610e6f5760808189031215610e275760008081fd5b610e2f61098c565b815181528482015185820152604080830151610e4a81610b67565b90820152606082810151610e5d81610b67565b90820152835291830191608001610e0e565b509695505050505050565b80518015158114610ba057600080fd5b600080600060608486031215610e9f57600080fd5b835167ffffffffffffffff80821115610eb757600080fd5b908501906101608288031215610ecc57600080fd5b610ed46109af565b610edd83610d34565b8152610eeb60208401610d3f565b6020820152610efc60408401610d3f565b6040820152610f0d60608401610c74565b606082015260808301516080820152610f2860a08401610d53565b60a0820152610f3960c08401610d34565b60c082015260e083015182811115610f5057600080fd5b610f5c89828601610d6b565b60e083015250610100610f70818501610d3f565b908201526101208381015183811115610f8857600080fd5b610f948a828701610db0565b918301919091525061014083810151908201529450610fb560208701610e7a565b93506040860151915080821115610fcb57600080fd5b50610fd886828701610d6b565b9150509250925092565b600060208284031215610ff457600080fd5b5051919050565b818103818111156108aa57634e487b7160e01b600052601160045260246000fdfea2646970667358221220419701a447cc0de596de268b3f9f715546b803ead18232d75602ee9a110a223d64736f6c63430008130033";

type GovernanceConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: GovernanceConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class Governance__factory extends ContractFactory {
  constructor(...args: GovernanceConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    _wormhole: string,
    overrides?: Overrides & { from?: string }
  ): Promise<Governance> {
    return super.deploy(_wormhole, overrides || {}) as Promise<Governance>;
  }
  override getDeployTransaction(
    _wormhole: string,
    overrides?: Overrides & { from?: string }
  ): TransactionRequest {
    return super.getDeployTransaction(_wormhole, overrides || {});
  }
  override attach(address: string): Governance {
    return super.attach(address) as Governance;
  }
  override connect(signer: Signer): Governance__factory {
    return super.connect(signer) as Governance__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): GovernanceInterface {
    return new utils.Interface(_abi) as GovernanceInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): Governance {
    return new Contract(address, _abi, signerOrProvider) as Governance;
  }
}

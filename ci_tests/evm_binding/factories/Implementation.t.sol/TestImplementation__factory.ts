/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type {
  TestImplementation,
  TestImplementationInterface,
} from "../../Implementation.t.sol/TestImplementation";

const _abi = [
  {
    type: "function",
    name: "getMigratesImmutables",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bool",
        internalType: "bool",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "incrementCounter",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "initialize",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "migrate",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "otherInitializer",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "upgrade",
    inputs: [
      {
        name: "newImplementation",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "upgradeCount",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "AdminChanged",
    inputs: [
      {
        name: "previousAdmin",
        type: "address",
        indexed: false,
        internalType: "address",
      },
      {
        name: "newAdmin",
        type: "address",
        indexed: false,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "BeaconUpgraded",
    inputs: [
      {
        name: "beacon",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Initialized",
    inputs: [
      {
        name: "version",
        type: "uint64",
        indexed: false,
        internalType: "uint64",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Upgraded",
    inputs: [
      {
        name: "implementation",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "error",
    name: "InvalidInitialization",
    inputs: [],
  },
  {
    type: "error",
    name: "NotInitializing",
    inputs: [],
  },
  {
    type: "error",
    name: "NotMigrating",
    inputs: [],
  },
  {
    type: "error",
    name: "OnlyDelegateCall",
    inputs: [],
  },
] as const;

const _bytecode =
  "0x60a080604052346100c5577ff0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a009081549060ff8260401c166100b657506001600160401b036002600160401b031982821601610071575b306080526040516106e890816100cb8239608051816106510152f35b6001600160401b031990911681179091556040519081527fc7f505b2f371ae2175ee4913f4499e1f2633a7b5936321eed1cdaeb6115181d290602090a1388080610055565b63f92ee8a960e01b8152600490fd5b600080fdfe6040608081526004908136101561001557600080fd5b600091823560e01c9081630900f010146104025781635b34b966146103a0578163689f90c31461035d5781638129fc1c146102a05781638fd3ab801461018f578163c2b3b94a1461008f575063c4128b6d1461007057600080fd5b3461008b578160031936011261008b57602091549051908152f35b5080fd5b90503461018b578260031936011261018b5760008051602061069383398151915290815460ff81851c16159167ffffffffffffffff821680159081610183575b6001149081610179575b159081610170575b50610162575067ffffffffffffffff198116600117835581610143575b50610107578280f35b805460ff60401b1916905551600181527fc7f505b2f371ae2175ee4913f4499e1f2633a7b5936321eed1cdaeb6115181d290602090a138808280f35b68ffffffffffffffffff191668010000000000000001178255386100fe565b845163f92ee8a960e01b8152fd5b905015386100e1565b303b1591506100d9565b8491506100cf565b8280fd5b9190503461018b578260031936011261018b576101aa61064e565b600080516020610693833981519152805467ffffffffffffffff808216600181019082821161028d5760ff84871c16908115610280575b5061027057169360ff7f7487ca88d037ca20519908b1ee7556206bef53bce0226a348750cb9d4f688e4e541615610262575068ffffffffffffffffff19168317680100000000000000001760ff60401b19169055519081527fc7f505b2f371ae2175ee4913f4499e1f2633a7b5936321eed1cdaeb6115181d290602090a180f35b8351632866815360e11b8152fd5b845163f92ee8a960e01b81528690fd5b90508282161115386101e1565b634e487b7160e01b885260118752602488fd5b90503461018b578260031936011261018b576102ba61064e565b60008051602061069383398151915290815460ff81851c16159167ffffffffffffffff821680159081610355575b600114908161034b575b159081610342575b50610162575067ffffffffffffffff198116600117835581610323575b50838055610107578280f35b68ffffffffffffffffff19166801000000000000000117825538610317565b905015386102fa565b303b1591506102f2565b8491506102e8565b50503461008b578160031936011261008b5760209060ff7f5443fea4dc453d96b81ce55b62e11a4094cc4cbb8a360956a7253cfdb42506cb541690519015158152f35b83833461008b578160031936011261008b5760ff60008051602061069383398151915254821c16156103f35750805460001981146103e057600101815580f35b506011602492634e487b7160e01b835252fd5b51631afcd79f60e31b81529050fd5b9190503461018b57602091826003193601126105865780356001600160a01b038116908181036105df5761043461064e565b3b156105f6577f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc80546001600160a01b031916821790557fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b8580a27f7487ca88d037ca20519908b1ee7556206bef53bce0226a348750cb9d4f688e4e9283549260ff84166105e35760ff199384166001178555303b156105df57805163011fa75760e71b81528681858183305af180156105a7576105b1575b50805163689f90c360e01b81529282848281305afa80156105a757610540575b505050507f5443fea4dc453d96b81ce55b62e11a4094cc4cbb8a360956a7253cfdb42506cb818154169055815416905580f35b82913d841161059f575b601f8301601f191685019167ffffffffffffffff83118684101761058a57505282018290031261058657518015150361018b573880808061050d565b8380fd5b604190634e487b7160e01b6000525260246000fd5b3d925061054a565b82513d89823e3d90fd5b67ffffffffffffffff81979297116105cc57865294386104ed565b634e487b7160e01b825260418452602482fd5b8580fd5b634e487b7160e01b865260018352602486fd5b5082608492519162461bcd60e51b8352820152602d60248201527f455243313936373a206e657720696d706c656d656e746174696f6e206973206e60448201526c1bdd08184818dbdb9d1c9858dd609a1b6064820152fd5b307f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03161461068057565b604051633c64f99360e21b8152600490fdfef0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00a26469706673582212201162a17089db67098179db68050069998f896256491c1d779226f18cdf447bcf64736f6c63430008130033";

type TestImplementationConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: TestImplementationConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class TestImplementation__factory extends ContractFactory {
  constructor(...args: TestImplementationConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    overrides?: Overrides & { from?: string }
  ): Promise<TestImplementation> {
    return super.deploy(overrides || {}) as Promise<TestImplementation>;
  }
  override getDeployTransaction(
    overrides?: Overrides & { from?: string }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  override attach(address: string): TestImplementation {
    return super.attach(address) as TestImplementation;
  }
  override connect(signer: Signer): TestImplementation__factory {
    return super.connect(signer) as TestImplementation__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): TestImplementationInterface {
    return new utils.Interface(_abi) as TestImplementationInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): TestImplementation {
    return new Contract(address, _abi, signerOrProvider) as TestImplementation;
  }
}

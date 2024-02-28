/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type {
  TrimmedAmountLib,
  TrimmedAmountLibInterface,
} from "../../TrimmedAmount.sol/TrimmedAmountLib";

const _abi = [
  {
    type: "function",
    name: "min",
    inputs: [
      {
        name: "a",
        type: "tuple",
        internalType: "struct TrimmedAmount",
        components: [
          {
            name: "amount",
            type: "uint64",
            internalType: "uint64",
          },
          {
            name: "decimals",
            type: "uint8",
            internalType: "uint8",
          },
        ],
      },
      {
        name: "b",
        type: "tuple",
        internalType: "struct TrimmedAmount",
        components: [
          {
            name: "amount",
            type: "uint64",
            internalType: "uint64",
          },
          {
            name: "decimals",
            type: "uint8",
            internalType: "uint8",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "",
        type: "tuple",
        internalType: "struct TrimmedAmount",
        components: [
          {
            name: "amount",
            type: "uint64",
            internalType: "uint64",
          },
          {
            name: "decimals",
            type: "uint8",
            internalType: "uint8",
          },
        ],
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "error",
    name: "AmountTooLarge",
    inputs: [
      {
        name: "amount",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "NumberOfDecimalsNotEqual",
    inputs: [
      {
        name: "decimals",
        type: "uint8",
        internalType: "uint8",
      },
      {
        name: "decimalsOther",
        type: "uint8",
        internalType: "uint8",
      },
    ],
  },
] as const;

const _bytecode =
  "0x6080806040523461001a5761021b9081610020823930815050f35b600080fdfe6080604052600436101561001257600080fd5b6000803560e01c630fe93ab11461002857600080fd5b3660031901608081126100ca576040136100c7576100446100d6565b67ffffffffffffffff9060043582811681036100d257815260243560ff811681036100d257602082015260403660431901126100ce576100826100d6565b9260443583811681036100ca5784526064359060ff821682036100c757506100b58460ff9360209384604098015261010c565b84519381511684520151166020820152f35b80fd5b5080fd5b8280fd5b8380fd5b604051906040820182811067ffffffffffffffff8211176100f657604052565b634e487b7160e01b600052604160045260246000fd5b90600060206101196100d6565b8281520152610127826101c1565b806101b1575b6101ad5761013a816101c1565b8061019d575b61017a5760ff60208301511660ff60208301511680820361017f57505067ffffffffffffffff80835116908251161160001461017a575090565b905090565b6044925060405191635ce6db6160e11b835260048301526024820152fd5b506101a7826101c1565b15610140565b5090565b506101bb816101c1565b1561012d565b67ffffffffffffffff8151161590816101d8575090565b60ff91506020015116159056fea2646970667358221220c6022385a88483d4379516c76de015dd9d65c8ffc7758bebfdc9e2cdc331ed5c64736f6c63430008130033";

type TrimmedAmountLibConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: TrimmedAmountLibConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class TrimmedAmountLib__factory extends ContractFactory {
  constructor(...args: TrimmedAmountLibConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    overrides?: Overrides & { from?: string }
  ): Promise<TrimmedAmountLib> {
    return super.deploy(overrides || {}) as Promise<TrimmedAmountLib>;
  }
  override getDeployTransaction(
    overrides?: Overrides & { from?: string }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  override attach(address: string): TrimmedAmountLib {
    return super.attach(address) as TrimmedAmountLib;
  }
  override connect(signer: Signer): TrimmedAmountLib__factory {
    return super.connect(signer) as TrimmedAmountLib__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): TrimmedAmountLibInterface {
    return new utils.Interface(_abi) as TrimmedAmountLibInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): TrimmedAmountLib {
    return new Contract(address, _abi, signerOrProvider) as TrimmedAmountLib;
  }
}

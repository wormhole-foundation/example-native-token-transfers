/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { StdError, StdErrorInterface } from "../../StdError.sol/StdError";

const _abi = [
  {
    type: "function",
    name: "arithmeticError",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "assertionError",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "divisionError",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "encodeStorageError",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "enumConversionError",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "indexOOBError",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "memOverflowError",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "popError",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "zeroVarError",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "view",
  },
] as const;

const _bytecode =
  "0x6080806040523461001a5761031f9081610020823930815050f35b600080fdfe60806040818152600436101561001457600080fd5b600091823560e01c90816305ee8612146102365750806310332977146102025780631de45560146101ce5780638995290f1461019a578063986c5f6814610166578063b22dc54d14610132578063b67689da146100fe578063d160e4de146100ca5763fa784a441461008557600080fd5b816003193601126100c657806100c2915190634e487b7160e01b602083015260126024830152602482526100b88261026e565b51918291826102a0565b0390f35b5080fd5b50816003193601126100c657806100c2915190634e487b7160e01b602083015260226024830152602482526100b88261026e565b50816003193601126100c657806100c2915190634e487b7160e01b602083015260516024830152602482526100b88261026e565b50816003193601126100c657806100c2915190634e487b7160e01b602083015260316024830152602482526100b88261026e565b50816003193601126100c657806100c2915190634e487b7160e01b602083015260416024830152602482526100b88261026e565b50816003193601126100c657806100c2915190634e487b7160e01b602083015260116024830152602482526100b88261026e565b50816003193601126100c657806100c2915190634e487b7160e01b602083015260216024830152602482526100b88261026e565b50816003193601126100c657806100c2915190634e487b7160e01b602083015260016024830152602482526100b88261026e565b9190508260031936011261026a576100c29250634e487b7160e01b602083015260326024830152602482526100b88261026e565b8280fd5b6060810190811067ffffffffffffffff82111761028a57604052565b634e487b7160e01b600052604160045260246000fd5b6020808252825181830181905290939260005b8281106102d557505060409293506000838284010152601f8019910116010190565b8181018601518482016040015285016102b356fea2646970667358221220601fd84fefea0116a9157ec3b62460ae8ebfa8b7530240905abdd3ca51af2b7c64736f6c63430008130033";

type StdErrorConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: StdErrorConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class StdError__factory extends ContractFactory {
  constructor(...args: StdErrorConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    overrides?: Overrides & { from?: string }
  ): Promise<StdError> {
    return super.deploy(overrides || {}) as Promise<StdError>;
  }
  override getDeployTransaction(
    overrides?: Overrides & { from?: string }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  override attach(address: string): StdError {
    return super.attach(address) as StdError;
  }
  override connect(signer: Signer): StdError__factory {
    return super.connect(signer) as StdError__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): StdErrorInterface {
    return new utils.Interface(_abi) as StdErrorInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): StdError {
    return new Contract(address, _abi, signerOrProvider) as StdError;
  }
}

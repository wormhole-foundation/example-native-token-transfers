/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { Utils, UtilsInterface } from "../../Utils.sol/Utils";

const _abi = [
  {
    type: "function",
    name: "assertSafeUpgradeableConstructor",
    inputs: [
      {
        name: "accesses",
        type: "tuple[]",
        internalType: "struct VmSafe.AccountAccess[]",
        components: [
          {
            name: "chainInfo",
            type: "tuple",
            internalType: "struct VmSafe.ChainInfo",
            components: [
              {
                name: "forkId",
                type: "uint256",
                internalType: "uint256",
              },
              {
                name: "chainId",
                type: "uint256",
                internalType: "uint256",
              },
            ],
          },
          {
            name: "kind",
            type: "VmSafe.AccountAccessKind",
            internalType: "enum VmSafe.AccountAccessKind",
          },
          {
            name: "account",
            type: "address",
            internalType: "address",
          },
          {
            name: "accessor",
            type: "address",
            internalType: "address",
          },
          {
            name: "initialized",
            type: "bool",
            internalType: "bool",
          },
          {
            name: "oldBalance",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "newBalance",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "deployedCode",
            type: "bytes",
            internalType: "bytes",
          },
          {
            name: "value",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "data",
            type: "bytes",
            internalType: "bytes",
          },
          {
            name: "reverted",
            type: "bool",
            internalType: "bool",
          },
          {
            name: "storageAccesses",
            type: "tuple[]",
            internalType: "struct VmSafe.StorageAccess[]",
            components: [
              {
                name: "account",
                type: "address",
                internalType: "address",
              },
              {
                name: "slot",
                type: "bytes32",
                internalType: "bytes32",
              },
              {
                name: "isWrite",
                type: "bool",
                internalType: "bool",
              },
              {
                name: "previousValue",
                type: "bytes32",
                internalType: "bytes32",
              },
              {
                name: "newValue",
                type: "bytes32",
                internalType: "bytes32",
              },
              {
                name: "reverted",
                type: "bool",
                internalType: "bool",
              },
            ],
          },
        ],
      },
    ],
    outputs: [],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "fetchQueuedTransferDigestsFromLogs",
    inputs: [
      {
        name: "logs",
        type: "tuple[]",
        internalType: "struct VmSafe.Log[]",
        components: [
          {
            name: "topics",
            type: "bytes32[]",
            internalType: "bytes32[]",
          },
          {
            name: "data",
            type: "bytes",
            internalType: "bytes",
          },
          {
            name: "emitter",
            type: "address",
            internalType: "address",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "",
        type: "bytes32[]",
        internalType: "bytes32[]",
      },
    ],
    stateMutability: "pure",
  },
] as const;

const _bytecode =
  "0x6080806040523461001a576109829081610020823930815050f35b600080fdfe6080604052600436101561001257600080fd5b60003560e01c8063638a14401461038a57637dec0d651461003257600080fd5b6020366003190112610360576001600160401b036004351161036057366023600435011215610360576004356004013561007361006e82610866565b610841565b602081838152019160249236848360051b600435010111610360578360043501905b848360051b60043501018210610249575050506000805b8251811015610126577f7f63c9251d82a933210c2b6d0b0f116252c3c116788120e64e8e8215df6f31626100ea6100e38386610938565b5151610915565b51146100ff575b6100fa906108f0565b6100ac565b906001810180911161011157906100f1565b83634e487b7160e01b60005260116004526000fd5b509061014061013761006e84610866565b92808452610866565b602083019290601f190136843760009160005b8151811015610204577f7f63c9251d82a933210c2b6d0b0f116252c3c116788120e64e8e8215df6f316261018a6100e38385610938565b511461019f575b61019a906108f0565b610153565b9260206101ac8584610938565b5101516020815191015190602081106101f2575b506101cb8285610938565b52600181018091116101dd5792610191565b85634e487b7160e01b60005260116004526000fd5b6000199060200360031b1b16386101c0565b84836040519182916020830190602084525180915260408301919060005b818110610230575050500390f35b8251845285945060209384019390920191600101610222565b81356001600160401b0381116103605760609182602319836004350136030112610360576040519283018381106001600160401b038211176103755760405286826004350101356001600160401b038111610360573660438285600435010101121561036057878184600435010101356102c561006e82610866565b9160208383815201903660448460051b838960043501010101116103605760448187600435010101915b60448460051b838960043501010101831061036557505050508352604482600435010135906001600160401b03821161036057879361034e606460209561034087968936918460043501010161089e565b86850152600435010161087d565b60408201528152019201919050610095565b600080fd5b82358152602092830192016102ef565b87634e487b7160e01b60005260416004526000fd5b6020366003190112610360576001600160401b03600435116103605736602360043501121561036057600435600401356103c661006e82610866565b9060208282815201903660248260051b60043501011161036057602460043501915b60248260051b6004350101831061058657600080855b805183101561050857906104128383610938565b51610160019160005b835180518210156104f35761043282604092610938565b510151610448575b610443906108f0565b61041b565b91507ff0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a006020610478848651610938565b510151036104885760019161043a565b60405162461bcd60e51b815260206004820152603960248201527f7570677261646561626c6520696d706c656d656e746174696f6e20636f6e737460448201527f727563746f722077726f74652073746f7261676520736c6f74000000000000006064820152608490fd5b5050915091610501906108f0565b91906103fe565b501561051057005b60405162461bcd60e51b815260206004820152604260248201527f7570677261646561626c6520696d706c656d656e746174696f6e20636f6e737460448201527f727563746f72206469646e27742064697361626c6520696e697469616c697a65606482015261727360f01b608482015260a490fd5b82356001600160401b038111610360576004358101360360231901906101a08083126103605760405192836101808101106001600160401b036101808601111761082b576040136103605761018083016101c08401106001600160401b036101c08501111761082b576101c0830160405260043582016024810135610180850190815260448201359285019290925290835260640135600b81101561036057602083015261063a608482600435010161087d565b604083015261064f60a482600435010161087d565b606083015261066460c4826004350101610891565b6080830152600435810160e481013560a084015261010481013560c08401526001600160401b036101249091013511610360576106af3660043583016101248101350160240161089e565b60e083015260043581016101448101356101008401526001600160401b036101649091013511610360576106f13660043583016101648101350160240161089e565b610120830152610708610184826004350101610891565b6101408301526101a4816004350101356001600160401b038111610360573660438284600435010101121561036057602481836004350101013561074e61006e82610866565b92602084838152019036604460c08502868460043501010101116103605760448482600435010101915b604460c0850286846004350101010183106107a65750505050506101608201528152602092830192016103e8565b60c083360312610360576040518060c08101106001600160401b0360c08301111761082b5760c0918183602093016040526107e08661087d565b815282860135838201526107f660408701610891565b6040820152606086013560608201526080860135608082015261081b60a08701610891565b60a0820152815201920191610778565b634e487b7160e01b600052604160045260246000fd5b6040519190601f01601f191682016001600160401b0381118382101761082b57604052565b6001600160401b03811161082b5760051b60200190565b35906001600160a01b038216820361036057565b3590811515820361036057565b81601f82011215610360578035906001600160401b03821161082b576108cd601f8301601f1916602001610841565b928284526020838301011161036057816000926020809301838601378301015290565b60001981146108ff5760010190565b634e487b7160e01b600052601160045260246000fd5b8051156109225760200190565b634e487b7160e01b600052603260045260246000fd5b80518210156109225760209160051b01019056fea264697066735822122090b65a9a349d7c2fc52881b3ff4f8bd13e831f030cf3f071ef1b9697df698f0664736f6c63430008130033";

type UtilsConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: UtilsConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class Utils__factory extends ContractFactory {
  constructor(...args: UtilsConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(overrides?: Overrides & { from?: string }): Promise<Utils> {
    return super.deploy(overrides || {}) as Promise<Utils>;
  }
  override getDeployTransaction(
    overrides?: Overrides & { from?: string }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  override attach(address: string): Utils {
    return super.attach(address) as Utils;
  }
  override connect(signer: Signer): Utils__factory {
    return super.connect(signer) as Utils__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): UtilsInterface {
    return new utils.Interface(_abi) as UtilsInterface;
  }
  static connect(address: string, signerOrProvider: Signer | Provider): Utils {
    return new Contract(address, _abi, signerOrProvider) as Utils;
  }
}

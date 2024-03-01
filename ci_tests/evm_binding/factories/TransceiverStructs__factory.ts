/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type {
  TransceiverStructs,
  TransceiverStructsInterface,
} from "../TransceiverStructs";

const _abi = [
  {
    type: "function",
    name: "buildAndEncodeTransceiverMessage",
    inputs: [
      {
        name: "prefix",
        type: "bytes4",
        internalType: "bytes4",
      },
      {
        name: "sourceNttManagerAddress",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "recipientNttManagerAddress",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "nttManagerMessage",
        type: "bytes",
        internalType: "bytes",
      },
      {
        name: "transceiverPayload",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [
      {
        name: "",
        type: "tuple",
        internalType: "struct TransceiverStructs.TransceiverMessage",
        components: [
          {
            name: "sourceNttManagerAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "recipientNttManagerAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "nttManagerPayload",
            type: "bytes",
            internalType: "bytes",
          },
          {
            name: "transceiverPayload",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "decodeTransceiverInit",
    inputs: [
      {
        name: "encoded",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [
      {
        name: "init",
        type: "tuple",
        internalType: "struct TransceiverStructs.TransceiverInit",
        components: [
          {
            name: "transceiverIdentifier",
            type: "bytes4",
            internalType: "bytes4",
          },
          {
            name: "nttManagerAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "nttManagerMode",
            type: "uint8",
            internalType: "uint8",
          },
          {
            name: "tokenAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "tokenDecimals",
            type: "uint8",
            internalType: "uint8",
          },
        ],
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "decodeTransceiverRegistration",
    inputs: [
      {
        name: "encoded",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [
      {
        name: "registration",
        type: "tuple",
        internalType: "struct TransceiverStructs.TransceiverRegistration",
        components: [
          {
            name: "transceiverIdentifier",
            type: "bytes4",
            internalType: "bytes4",
          },
          {
            name: "transceiverChainId",
            type: "uint16",
            internalType: "uint16",
          },
          {
            name: "transceiverAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
        ],
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "encodeNativeTokenTransfer",
    inputs: [
      {
        name: "m",
        type: "tuple",
        internalType: "struct TransceiverStructs.NativeTokenTransfer",
        components: [
          {
            name: "amount",
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
            name: "sourceToken",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "to",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "toChain",
            type: "uint16",
            internalType: "uint16",
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
    name: "encodeNttManagerMessage",
    inputs: [
      {
        name: "m",
        type: "tuple",
        internalType: "struct TransceiverStructs.NttManagerMessage",
        components: [
          {
            name: "id",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "sender",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "payload",
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
    name: "encodeTransceiverInit",
    inputs: [
      {
        name: "init",
        type: "tuple",
        internalType: "struct TransceiverStructs.TransceiverInit",
        components: [
          {
            name: "transceiverIdentifier",
            type: "bytes4",
            internalType: "bytes4",
          },
          {
            name: "nttManagerAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "nttManagerMode",
            type: "uint8",
            internalType: "uint8",
          },
          {
            name: "tokenAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "tokenDecimals",
            type: "uint8",
            internalType: "uint8",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "encodeTransceiverInstruction",
    inputs: [
      {
        name: "instruction",
        type: "tuple",
        internalType: "struct TransceiverStructs.TransceiverInstruction",
        components: [
          {
            name: "index",
            type: "uint8",
            internalType: "uint8",
          },
          {
            name: "payload",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "encodeTransceiverInstructions",
    inputs: [
      {
        name: "instructions",
        type: "tuple[]",
        internalType: "struct TransceiverStructs.TransceiverInstruction[]",
        components: [
          {
            name: "index",
            type: "uint8",
            internalType: "uint8",
          },
          {
            name: "payload",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "encodeTransceiverMessage",
    inputs: [
      {
        name: "prefix",
        type: "bytes4",
        internalType: "bytes4",
      },
      {
        name: "m",
        type: "tuple",
        internalType: "struct TransceiverStructs.TransceiverMessage",
        components: [
          {
            name: "sourceNttManagerAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "recipientNttManagerAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "nttManagerPayload",
            type: "bytes",
            internalType: "bytes",
          },
          {
            name: "transceiverPayload",
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
    name: "encodeTransceiverRegistration",
    inputs: [
      {
        name: "registration",
        type: "tuple",
        internalType: "struct TransceiverStructs.TransceiverRegistration",
        components: [
          {
            name: "transceiverIdentifier",
            type: "bytes4",
            internalType: "bytes4",
          },
          {
            name: "transceiverChainId",
            type: "uint16",
            internalType: "uint16",
          },
          {
            name: "transceiverAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "nttManagerMessageDigest",
    inputs: [
      {
        name: "sourceChainId",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "m",
        type: "tuple",
        internalType: "struct TransceiverStructs.NttManagerMessage",
        components: [
          {
            name: "id",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "sender",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "payload",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
    ],
    outputs: [
      {
        name: "",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "parseNativeTokenTransfer",
    inputs: [
      {
        name: "encoded",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [
      {
        name: "nativeTokenTransfer",
        type: "tuple",
        internalType: "struct TransceiverStructs.NativeTokenTransfer",
        components: [
          {
            name: "amount",
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
            name: "sourceToken",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "to",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "toChain",
            type: "uint16",
            internalType: "uint16",
          },
        ],
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "parseNttManagerMessage",
    inputs: [
      {
        name: "encoded",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [
      {
        name: "nttManagerMessage",
        type: "tuple",
        internalType: "struct TransceiverStructs.NttManagerMessage",
        components: [
          {
            name: "id",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "sender",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "payload",
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
    name: "parseTransceiverAndNttManagerMessage",
    inputs: [
      {
        name: "expectedPrefix",
        type: "bytes4",
        internalType: "bytes4",
      },
      {
        name: "payload",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [
      {
        name: "",
        type: "tuple",
        internalType: "struct TransceiverStructs.TransceiverMessage",
        components: [
          {
            name: "sourceNttManagerAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "recipientNttManagerAddress",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "nttManagerPayload",
            type: "bytes",
            internalType: "bytes",
          },
          {
            name: "transceiverPayload",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
      {
        name: "",
        type: "tuple",
        internalType: "struct TransceiverStructs.NttManagerMessage",
        components: [
          {
            name: "id",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "sender",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "payload",
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
    name: "parseTransceiverInstructionChecked",
    inputs: [
      {
        name: "encoded",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [
      {
        name: "instruction",
        type: "tuple",
        internalType: "struct TransceiverStructs.TransceiverInstruction",
        components: [
          {
            name: "index",
            type: "uint8",
            internalType: "uint8",
          },
          {
            name: "payload",
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
    name: "parseTransceiverInstructionUnchecked",
    inputs: [
      {
        name: "encoded",
        type: "bytes",
        internalType: "bytes",
      },
      {
        name: "offset",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "instruction",
        type: "tuple",
        internalType: "struct TransceiverStructs.TransceiverInstruction",
        components: [
          {
            name: "index",
            type: "uint8",
            internalType: "uint8",
          },
          {
            name: "payload",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
      {
        name: "nextOffset",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "parseTransceiverInstructions",
    inputs: [
      {
        name: "encoded",
        type: "bytes",
        internalType: "bytes",
      },
      {
        name: "numEnabledTransceivers",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "",
        type: "tuple[]",
        internalType: "struct TransceiverStructs.TransceiverInstruction[]",
        components: [
          {
            name: "index",
            type: "uint8",
            internalType: "uint8",
          },
          {
            name: "payload",
            type: "bytes",
            internalType: "bytes",
          },
        ],
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "error",
    name: "IncorrectPrefix",
    inputs: [
      {
        name: "prefix",
        type: "bytes4",
        internalType: "bytes4",
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
    name: "PayloadTooLong",
    inputs: [
      {
        name: "size",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "UnorderedInstructions",
    inputs: [],
  },
] as const;

const _bytecode =
  "0x6080806040523461001a576114b69081610020823930815050f35b600080fdfe608060408181526004918236101561001657600080fd5b600092833560e01c918263054a7d8414610c5457508163055cedbd14610ad457816308a700d6146109d2578163107383fb146109875781631185b23c146108dd57816322cebdee146108a55781632b9f4796146107c35781633906001d1461071b57816340d2f75a146106ea578163433e3f29146106395781635f396d4b146105ba5781638b4979b814610574578163a733bdaa14610448578163b3f07bbd146103bd578163b620e87214610262578163c9bc77bb14610178575063eeca1f60146100e057600080fd5b6060366003190112610174578051906100f882610d5e565b610100610db5565b918281526024359361ffff851685036101715750838161016d95602085940152604435928391015282519363ffffffff60e01b16602085015261ffff60f01b9060f01b16602484015260268301526026825261015b82610d5e565b51918291602083526020830190610df4565b0390f35b80fd5b5080fd5b9050602036600319011261025e5780356001600160401b03811161025a576101a39036908301610e30565b918051926101b084610cf7565b848452602084018581528285019186835260608601948786526080870197885263ffffffff60e01b91828282015160e01b1688526024810151845260ff60258201511685526045810151875260ff6046820151168952516046810361023d5760a08860ff8b8a8a838b8b8b8451985116885251602088015251169085015251606084015251166080820152f35b85516355c5b3e360e11b8152918201526046602482015260449150fd5b8380fd5b8280fd5b905061026d36610f3d565b9390916001928381015191849260ff8091169061028989610e19565b9861029689519a8b610d94565b808a526102a5601f1991610e19565b01865b8181106103a05750508592865b838110610327575050505050906102cb916110b6565b825192602080850191818652865180935281818701918460051b880101970193905b8382106102fa5786880387f35b90919293948380610316839a603f198b82030186528951610f6e565b9997019594939190910191016102ed565b90919293956103429061033b9b999b6113e3565b50866113fd565b969084815116918315159081610395575b506103855791610377828b979695946103708261037d969a611456565b528b611456565b50611431565b9997996102b5565b8a516338f91f7960e11b81528490fd5b905082111538610353565b6020906103ae9b999b6113e3565b82828c010152019997996102a8565b8284816003193601126101715782359061ffff8216820361017157602435906001600160401b03821161017157506103fd60209461040292369101610f8e565b610fd8565b61043e6022845180938782019561ffff60f01b9060f01b16865261042e815180928a8686019101610dd1565b8101036002810184520182610d94565b5190209051908152f35b6020838536600319018313610171576001600160401b0393803585811161025e576104769036908301610e30565b9280519461048386610d28565b815161048e81610d43565b8481528482820152865280860190848252828701938585526060880195865263ffffffff60e01b8188015160e01b16632653951560e21b810361055e5750600587015160ff600d890151918b8751936104e685610d43565b16835216838201528852602d8701518352604d870151855261ffff9687604f82015116875251604f810361054157505060ff8160a09985519951908151168a5201511690870152519085015251606084015251166080820152f35b84516355c5b3e360e11b815291820152604f602482015260449150fd5b84516356d2569d60e01b81529182015260249150fd5b82846020366003190112610171578235906001600160401b03821161017157506103fd61016d936105a792369101610f8e565b9051918291602083526020830190610df4565b82846020366003190112610171578235906001600160401b038211610171575061016d926105ea91369101610e30565b906105f36113e3565b506106276105ff6113e3565b9260ff600182015116845261061b60ff600283015116826111d1565b919060208601526110b6565b51918291602083526020830190610f6e565b838360203660031901126101745782356001600160401b03811161025e576106649036908501610e30565b9181519261067184610d5e565b8184526020840182815283850192835263ffffffff60e01b808784015160e01b16865261ffff92836006820151168352602681015185525196602688036106cc57506060965084519551168552511660208401525190820152f35b85516355c5b3e360e11b815290810188905260266024820152604490fd5b826106fd6106f736610f3d565b906113fd565b825183815292839261071191840190610f6e565b9060208301520390f35b9050600319828136011261025a57610731610db5565b91602435916001600160401b03908184116107bf5760809084360301126107bb5784519561075e87610d28565b8383013587526024840135602088015260448401358281116101745761078990843691870101610e30565b868801526064840135918211610171575061016d95926105a794926107b19236920101610e30565b60608301526112bd565b8580fd5b8680fd5b91905060031936019260a0841261017157818051946107e186610d28565b12610171578151926107f284610d43565b356001600160401b038116810361017457835260243560ff8116810361017457602084019081528385526044358060208701526064359182858801526084359361ffff85168503610171575083606061016d980152519451845195632653951560e21b602088015260ff60f81b9060f81b1660248701526001600160401b0360c01b9060c01b166025860152602d850152604d84015261ffff60f01b9060f01b16606d830152604f825261015b82610d28565b82846020366003190112610171578235906001600160401b03821161017157506108d861016d936105a792369101610e86565b611394565b828460a0366003190112610171576108f3610db5565b926001600160401b0360643581811161025a576109139036908401610e30565b926084359182116101715750916109336109669261016d94369101610e30565b9461093c61136e565b50845195869261094b84610d28565b602435845260443560208501528684015260608301526112bd565b6109798351948486958652850190610ed5565b908382036020850152610df4565b82846020366003190112610171578235906001600160401b03821161017157506109ba61016d936109bf92369101610e30565b611078565b9051918291602083526020830190610f16565b90508160031936011261025e576109e7610db5565b92602435906001600160401b0382116101715750610a089036908301610e30565b90610a1161136e565b50610a1a611057565b50610a2361136e565b9363ffffffff60e01b808385015160e01b1691168103610abe575050610a9d81602461016d930151855260448101516020860152610a9761ffff91610a8b6002610a7385604685015116846110e1565b919095898b0196875281838601015116910183611249565b919060608901526110b6565b51611078565b610ab08351948486958652850190610ed5565b908382036020850152610f16565b83516356d2569d60e01b81529182015260249150fd5b60209291503660031901831361025a578035906001600160401b03908183116107bb57366023840112156107bb578281013591610b1083610e19565b93610b1d86519586610d94565b838552868501906024809560051b82010192368411610c5057858201925b848410610c26575050505050825160ff8111610c1457505050805190606094905b828210610bb357505090610ba4602161016d93835196879160ff60f81b9060f81b1687830152610b9481518092898686019101610dd1565b8101036001810187520185610d94565b51928284938452830190610df4565b9094610c0e90610c0886610bd0610bca8a87611456565b51611394565b9287519381610be88693518092868087019101610dd1565b8201610bfc82518093868085019101610dd1565b01038084520182610d94565b95611431565b90610b5c565b845163a341969160e01b815291820152fd5b8335828111610c4c578a91610c4183928a3691880101610e86565b815201930192610b3b565b8b80fd5b8980fd5b848460a036600319011261017457610c6b83610cf7565b610c73610db5565b91828452602435908160208601526044359160ff83168303610174578284870152606435908160608801526084359260ff84168403610171575082608061016d98015284519563ffffffff60e01b166020870152602486015260ff60f81b809360f81b166044860152604585015260f81b1660658301526046825261015b82610d28565b60a081019081106001600160401b03821117610d1257604052565b634e487b7160e01b600052604160045260246000fd5b608081019081106001600160401b03821117610d1257604052565b604081019081106001600160401b03821117610d1257604052565b606081019081106001600160401b03821117610d1257604052565b602081019081106001600160401b03821117610d1257604052565b90601f801991011681019081106001600160401b03821117610d1257604052565b600435906001600160e01b031982168203610dcc57565b600080fd5b60005b838110610de45750506000910152565b8181015183820152602001610dd4565b90602091610e0d81518092818552858086019101610dd1565b601f01601f1916010190565b6001600160401b038111610d125760051b60200190565b81601f82011215610dcc578035906001600160401b038211610d125760405192610e64601f8401601f191660200185610d94565b82845260208383010111610dcc57816000926020809301838601378301015290565b9190604083820312610dcc5760405190610e9f82610d43565b8193803560ff81168103610dcc5783526020810135916001600160401b038311610dcc57602092610ed09201610e30565b910152565b610f139181518152602082015160208201526060610f026040840151608060408501526080840190610df4565b920151906060818403910152610df4565b90565b9060606040610f139380518452602081015160208501520151918160408201520190610df4565b6040600319820112610dcc57600435906001600160401b038211610dcc57610f6791600401610e30565b9060243590565b9060406020610f139360ff81511684520151918160208201520190610df4565b9190606083820312610dcc5760405190610fa782610d5e565b819380358352602081013560208401526040810135916001600160401b038311610dcc57604092610ed09201610e30565b6040810180515161ffff811161103f57506062610f1391519283519360208251920151946040519586936020850152604084015261ffff60f01b9060f01b16606083015261102f8151809260208686019101610dd1565b8101036042810184520182610d94565b6024906040519063a341969160e01b82526004820152fd5b6040519061106482610d5e565b606060408360008152600060208201520152565b906110b4611084611057565b9260208101518452604081015160208501526110a861ffff60428301511682611159565b919060408601526110b6565b565b51908082036110c3575050565b60449250604051916355c5b3e360e11b835260048301526024820152fd5b9091821561113b57826046019160405193601f8116918215611132575b6046838701938385019201015b8184106111225750508452601f01601f1916604052565b805184526020938401930161110b565b602092506110fe565b91505060405161114a81610d79565b60008152600036813790604690565b909182156111b357826042019160405193601f81169182156111aa575b6042838701938385019201015b81841061119a5750508452601f01601f1916604052565b8051845260209384019301611183565b60209250611176565b9150506040516111c281610d79565b60008152600036813790604290565b9091821561122b57826002019160405193601f8116918215611222575b6002838701938385019201015b8184106112125750508452601f01601f1916604052565b80518452602093840193016111fb565b602092506111ee565b91505060405161123a81610d79565b60008152600036813790600290565b929082156112a0578281019260405194601f8216928315611297575b838701938385019201015b8184106112875750508452601f01601f1916604052565b8051845260209384019301611270565b60209350611265565b925090506040516112b081610d79565b6000815260003681379190565b604082018051519061ffff9182811161103f575080515191606085019081515190811161103f575091610f13939160689351918251916020885198015190519060405198899663ffffffff60e01b1660208801526024870152604486015261ffff60f01b809260f01b166064860152611340815180926020606689019101610dd1565b84019160f01b16606682015261135f8251809360208785019101610dd1565b01036048810184520182610d94565b6040519061137b82610d28565b6060808360008152600060208201528160408201520152565b6020810180515160ff811161103f57506022610f13915192835190519360405194859260ff60f81b809260f81b16602085015260f81b16602183015261042e8151809260208686019101610dd1565b604051906113f082610d43565b6060602083600081520152565b91906114289061140b6113e3565b93600260ff81848401826001820151168952015116920190611249565b91906020840152565b60001981146114405760010190565b634e487b7160e01b600052601160045260246000fd5b805182101561146a5760209160051b010190565b634e487b7160e01b600052603260045260246000fdfea26469706673582212203d2c6885c0a0a3ea72655286a75287e498db894cf6c8e6f172fa390e87bddec064736f6c63430008130033";

type TransceiverStructsConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: TransceiverStructsConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class TransceiverStructs__factory extends ContractFactory {
  constructor(...args: TransceiverStructsConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    overrides?: Overrides & { from?: string }
  ): Promise<TransceiverStructs> {
    return super.deploy(overrides || {}) as Promise<TransceiverStructs>;
  }
  override getDeployTransaction(
    overrides?: Overrides & { from?: string }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  override attach(address: string): TransceiverStructs {
    return super.attach(address) as TransceiverStructs;
  }
  override connect(signer: Signer): TransceiverStructs__factory {
    return super.connect(signer) as TransceiverStructs__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): TransceiverStructsInterface {
    return new utils.Interface(_abi) as TransceiverStructsInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): TransceiverStructs {
    return new Contract(address, _abi, signerOrProvider) as TransceiverStructs;
  }
}

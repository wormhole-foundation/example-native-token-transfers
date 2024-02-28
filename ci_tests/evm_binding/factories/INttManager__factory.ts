/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer, utils } from "ethers";
import type { Provider } from "@ethersproject/providers";
import type { INttManager, INttManagerInterface } from "../INttManager";

const _abi = [
  {
    type: "function",
    name: "attestationReceived",
    inputs: [
      {
        name: "sourceChainId",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "sourceNttManagerAddress",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "payload",
        type: "tuple",
        internalType: "struct TransceiverStructs.NttManagerMessage",
        components: [
          {
            name: "sequence",
            type: "uint64",
            internalType: "uint64",
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
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "chainId",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint16",
        internalType: "uint16",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "completeInboundQueuedTransfer",
    inputs: [
      {
        name: "digest",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "completeOutboundQueuedTransfer",
    inputs: [
      {
        name: "queueSequence",
        type: "uint64",
        internalType: "uint64",
      },
    ],
    outputs: [
      {
        name: "msgSequence",
        type: "uint64",
        internalType: "uint64",
      },
    ],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "executeMsg",
    inputs: [
      {
        name: "sourceChainId",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "sourceNttManagerAddress",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "message",
        type: "tuple",
        internalType: "struct TransceiverStructs.NttManagerMessage",
        components: [
          {
            name: "sequence",
            type: "uint64",
            internalType: "uint64",
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
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "getMode",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint8",
        internalType: "uint8",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getPeer",
    inputs: [
      {
        name: "chainId_",
        type: "uint16",
        internalType: "uint16",
      },
    ],
    outputs: [
      {
        name: "",
        type: "tuple",
        internalType: "struct INttManagerState.NttManagerPeer",
        components: [
          {
            name: "peerAddress",
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
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getThreshold",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint8",
        internalType: "uint8",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isMessageApproved",
    inputs: [
      {
        name: "digest",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
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
    name: "isMessageExecuted",
    inputs: [
      {
        name: "digest",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
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
    name: "messageAttestations",
    inputs: [
      {
        name: "digest",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
    outputs: [
      {
        name: "count",
        type: "uint8",
        internalType: "uint8",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "nextMessageSequence",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint64",
        internalType: "uint64",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "pause",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "quoteDeliveryPrice",
    inputs: [
      {
        name: "recipientChain",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "transceiverInstructions",
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
      {
        name: "enabledTransceivers",
        type: "address[]",
        internalType: "address[]",
      },
    ],
    outputs: [
      {
        name: "",
        type: "uint256[]",
        internalType: "uint256[]",
      },
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "removeTransceiver",
    inputs: [
      {
        name: "transceiver",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setInboundLimit",
    inputs: [
      {
        name: "limit",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "chainId",
        type: "uint16",
        internalType: "uint16",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setOutboundLimit",
    inputs: [
      {
        name: "limit",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setPeer",
    inputs: [
      {
        name: "peerChainId",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "peerContract",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "decimals",
        type: "uint8",
        internalType: "uint8",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setThreshold",
    inputs: [
      {
        name: "threshold",
        type: "uint8",
        internalType: "uint8",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setTransceiver",
    inputs: [
      {
        name: "transceiver",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "token",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "tokenDecimals",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint8",
        internalType: "uint8",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "transceiverAttestedToMessage",
    inputs: [
      {
        name: "digest",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "index",
        type: "uint8",
        internalType: "uint8",
      },
    ],
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
    name: "transfer",
    inputs: [
      {
        name: "amount",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "recipientChain",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "recipient",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
    outputs: [
      {
        name: "msgId",
        type: "uint64",
        internalType: "uint64",
      },
    ],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "transfer",
    inputs: [
      {
        name: "amount",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "recipientChain",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "recipient",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "shouldQueue",
        type: "bool",
        internalType: "bool",
      },
      {
        name: "encodedInstructions",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [
      {
        name: "msgId",
        type: "uint64",
        internalType: "uint64",
      },
    ],
    stateMutability: "payable",
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
    type: "error",
    name: "BurnAmountDifferentThanBalanceDiff",
    inputs: [
      {
        name: "burnAmount",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "balanceDiff",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "DeliveryPaymentTooLow",
    inputs: [
      {
        name: "requiredPayment",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "providedPayment",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "InvalidMode",
    inputs: [
      {
        name: "mode",
        type: "uint8",
        internalType: "uint8",
      },
    ],
  },
  {
    type: "error",
    name: "InvalidPeer",
    inputs: [
      {
        name: "chainId",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "peerAddress",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
  },
  {
    type: "error",
    name: "InvalidPeerChainIdZero",
    inputs: [],
  },
  {
    type: "error",
    name: "InvalidPeerDecimals",
    inputs: [],
  },
  {
    type: "error",
    name: "InvalidPeerZeroAddress",
    inputs: [],
  },
  {
    type: "error",
    name: "InvalidRecipient",
    inputs: [],
  },
  {
    type: "error",
    name: "InvalidTargetChain",
    inputs: [
      {
        name: "targetChain",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "thisChain",
        type: "uint16",
        internalType: "uint16",
      },
    ],
  },
  {
    type: "error",
    name: "MessageNotApproved",
    inputs: [
      {
        name: "msgHash",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
  },
  {
    type: "error",
    name: "RefundFailed",
    inputs: [
      {
        name: "refundAmount",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "RetrievedIncorrectRegisteredTransceivers",
    inputs: [
      {
        name: "retrieved",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "registered",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "ThresholdTooHigh",
    inputs: [
      {
        name: "threshold",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "transceivers",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "TransceiverAlreadyAttestedToMessage",
    inputs: [
      {
        name: "nttManagerMessageHash",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
  },
  {
    type: "error",
    name: "TransferAmountHasDust",
    inputs: [
      {
        name: "amount",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "dust",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "UnexpectedDeployer",
    inputs: [
      {
        name: "expectedOwner",
        type: "address",
        internalType: "address",
      },
      {
        name: "owner",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "ZeroAmount",
    inputs: [],
  },
  {
    type: "error",
    name: "ZeroThreshold",
    inputs: [],
  },
] as const;

export class INttManager__factory {
  static readonly abi = _abi;
  static createInterface(): INttManagerInterface {
    return new utils.Interface(_abi) as INttManagerInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): INttManager {
    return new Contract(address, _abi, signerOrProvider) as INttManager;
  }
}

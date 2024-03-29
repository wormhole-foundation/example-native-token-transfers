/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import type {
  BaseContract,
  BigNumberish,
  BytesLike,
  FunctionFragment,
  Result,
  Interface,
  EventFragment,
  AddressLike,
  ContractRunner,
  ContractMethod,
  Listener,
} from "ethers";
import type {
  TypedContractEvent,
  TypedDeferredTopicFilter,
  TypedEventLog,
  TypedLogDescription,
  TypedListener,
  TypedContractMethod,
} from "./common.js";

export declare namespace IWormholeTransceiver {
  export type WormholeTransceiverInstructionStruct = {
    shouldSkipRelayerSend: boolean;
  };

  export type WormholeTransceiverInstructionStructOutput = [
    shouldSkipRelayerSend: boolean
  ] & { shouldSkipRelayerSend: boolean };
}

export declare namespace TransceiverStructs {
  export type TransceiverInstructionStruct = {
    index: BigNumberish;
    payload: BytesLike;
  };

  export type TransceiverInstructionStructOutput = [
    index: bigint,
    payload: string
  ] & { index: bigint; payload: string };

  export type TransceiverMessageStruct = {
    sourceNttManagerAddress: BytesLike;
    recipientNttManagerAddress: BytesLike;
    nttManagerPayload: BytesLike;
    transceiverPayload: BytesLike;
  };

  export type TransceiverMessageStructOutput = [
    sourceNttManagerAddress: string,
    recipientNttManagerAddress: string,
    nttManagerPayload: string,
    transceiverPayload: string
  ] & {
    sourceNttManagerAddress: string;
    recipientNttManagerAddress: string;
    nttManagerPayload: string;
    transceiverPayload: string;
  };
}

export interface WormholeTransceiverInterface extends Interface {
  getFunction(
    nameOrSignature:
      | "consistencyLevel"
      | "encodeWormholeTransceiverInstruction"
      | "gasLimit"
      | "getMigratesImmutables"
      | "getNttManagerOwner"
      | "getNttManagerToken"
      | "getWormholePeer"
      | "initialize"
      | "isPaused"
      | "isSpecialRelayingEnabled"
      | "isVAAConsumed"
      | "isWormholeEvmChain"
      | "isWormholeRelayingEnabled"
      | "migrate"
      | "nttManager"
      | "nttManagerToken"
      | "owner"
      | "parseWormholeTransceiverInstruction"
      | "pauser"
      | "quoteDeliveryPrice"
      | "receiveMessage"
      | "receiveWormholeMessages"
      | "sendMessage"
      | "setIsSpecialRelayingEnabled"
      | "setIsWormholeEvmChain"
      | "setIsWormholeRelayingEnabled"
      | "setWormholePeer"
      | "specialRelayer"
      | "transferOwnership"
      | "transferPauserCapability"
      | "transferTransceiverOwnership"
      | "upgrade"
      | "wormhole"
      | "wormholeRelayer"
  ): FunctionFragment;

  getEvent(
    nameOrSignatureOrTopic:
      | "AdminChanged"
      | "BeaconUpgraded"
      | "Initialized"
      | "NotPaused"
      | "OwnershipTransferred"
      | "Paused"
      | "PauserTransferred"
      | "ReceivedMessage"
      | "ReceivedRelayedMessage"
      | "RelayingInfo"
      | "SendTransceiverMessage"
      | "SetIsSpecialRelayingEnabled"
      | "SetIsWormholeEvmChain"
      | "SetIsWormholeRelayingEnabled"
      | "SetWormholePeer"
      | "Upgraded"
  ): EventFragment;

  encodeFunctionData(
    functionFragment: "consistencyLevel",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "encodeWormholeTransceiverInstruction",
    values: [IWormholeTransceiver.WormholeTransceiverInstructionStruct]
  ): string;
  encodeFunctionData(functionFragment: "gasLimit", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "getMigratesImmutables",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "getNttManagerOwner",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "getNttManagerToken",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "getWormholePeer",
    values: [BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "initialize",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "isPaused", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "isSpecialRelayingEnabled",
    values: [BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "isVAAConsumed",
    values: [BytesLike]
  ): string;
  encodeFunctionData(
    functionFragment: "isWormholeEvmChain",
    values: [BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "isWormholeRelayingEnabled",
    values: [BigNumberish]
  ): string;
  encodeFunctionData(functionFragment: "migrate", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "nttManager",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "nttManagerToken",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "owner", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "parseWormholeTransceiverInstruction",
    values: [BytesLike]
  ): string;
  encodeFunctionData(functionFragment: "pauser", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "quoteDeliveryPrice",
    values: [BigNumberish, TransceiverStructs.TransceiverInstructionStruct]
  ): string;
  encodeFunctionData(
    functionFragment: "receiveMessage",
    values: [BytesLike]
  ): string;
  encodeFunctionData(
    functionFragment: "receiveWormholeMessages",
    values: [BytesLike, BytesLike[], BytesLike, BigNumberish, BytesLike]
  ): string;
  encodeFunctionData(
    functionFragment: "sendMessage",
    values: [
      BigNumberish,
      TransceiverStructs.TransceiverInstructionStruct,
      BytesLike,
      BytesLike
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "setIsSpecialRelayingEnabled",
    values: [BigNumberish, boolean]
  ): string;
  encodeFunctionData(
    functionFragment: "setIsWormholeEvmChain",
    values: [BigNumberish, boolean]
  ): string;
  encodeFunctionData(
    functionFragment: "setIsWormholeRelayingEnabled",
    values: [BigNumberish, boolean]
  ): string;
  encodeFunctionData(
    functionFragment: "setWormholePeer",
    values: [BigNumberish, BytesLike]
  ): string;
  encodeFunctionData(
    functionFragment: "specialRelayer",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "transferOwnership",
    values: [AddressLike]
  ): string;
  encodeFunctionData(
    functionFragment: "transferPauserCapability",
    values: [AddressLike]
  ): string;
  encodeFunctionData(
    functionFragment: "transferTransceiverOwnership",
    values: [AddressLike]
  ): string;
  encodeFunctionData(
    functionFragment: "upgrade",
    values: [AddressLike]
  ): string;
  encodeFunctionData(functionFragment: "wormhole", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "wormholeRelayer",
    values?: undefined
  ): string;

  decodeFunctionResult(
    functionFragment: "consistencyLevel",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "encodeWormholeTransceiverInstruction",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "gasLimit", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "getMigratesImmutables",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "getNttManagerOwner",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "getNttManagerToken",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "getWormholePeer",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "initialize", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "isPaused", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "isSpecialRelayingEnabled",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "isVAAConsumed",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "isWormholeEvmChain",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "isWormholeRelayingEnabled",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "migrate", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "nttManager", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "nttManagerToken",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "owner", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "parseWormholeTransceiverInstruction",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "pauser", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "quoteDeliveryPrice",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "receiveMessage",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "receiveWormholeMessages",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "sendMessage",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "setIsSpecialRelayingEnabled",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "setIsWormholeEvmChain",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "setIsWormholeRelayingEnabled",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "setWormholePeer",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "specialRelayer",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "transferOwnership",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "transferPauserCapability",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "transferTransceiverOwnership",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "upgrade", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "wormhole", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "wormholeRelayer",
    data: BytesLike
  ): Result;
}

export namespace AdminChangedEvent {
  export type InputTuple = [previousAdmin: AddressLike, newAdmin: AddressLike];
  export type OutputTuple = [previousAdmin: string, newAdmin: string];
  export interface OutputObject {
    previousAdmin: string;
    newAdmin: string;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace BeaconUpgradedEvent {
  export type InputTuple = [beacon: AddressLike];
  export type OutputTuple = [beacon: string];
  export interface OutputObject {
    beacon: string;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace InitializedEvent {
  export type InputTuple = [version: BigNumberish];
  export type OutputTuple = [version: bigint];
  export interface OutputObject {
    version: bigint;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace NotPausedEvent {
  export type InputTuple = [notPaused: boolean];
  export type OutputTuple = [notPaused: boolean];
  export interface OutputObject {
    notPaused: boolean;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace OwnershipTransferredEvent {
  export type InputTuple = [previousOwner: AddressLike, newOwner: AddressLike];
  export type OutputTuple = [previousOwner: string, newOwner: string];
  export interface OutputObject {
    previousOwner: string;
    newOwner: string;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace PausedEvent {
  export type InputTuple = [paused: boolean];
  export type OutputTuple = [paused: boolean];
  export interface OutputObject {
    paused: boolean;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace PauserTransferredEvent {
  export type InputTuple = [oldPauser: AddressLike, newPauser: AddressLike];
  export type OutputTuple = [oldPauser: string, newPauser: string];
  export interface OutputObject {
    oldPauser: string;
    newPauser: string;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace ReceivedMessageEvent {
  export type InputTuple = [
    digest: BytesLike,
    emitterChainId: BigNumberish,
    emitterAddress: BytesLike,
    sequence: BigNumberish
  ];
  export type OutputTuple = [
    digest: string,
    emitterChainId: bigint,
    emitterAddress: string,
    sequence: bigint
  ];
  export interface OutputObject {
    digest: string;
    emitterChainId: bigint;
    emitterAddress: string;
    sequence: bigint;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace ReceivedRelayedMessageEvent {
  export type InputTuple = [
    digest: BytesLike,
    emitterChainId: BigNumberish,
    emitterAddress: BytesLike
  ];
  export type OutputTuple = [
    digest: string,
    emitterChainId: bigint,
    emitterAddress: string
  ];
  export interface OutputObject {
    digest: string;
    emitterChainId: bigint;
    emitterAddress: string;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace RelayingInfoEvent {
  export type InputTuple = [
    relayingType: BigNumberish,
    deliveryPayment: BigNumberish
  ];
  export type OutputTuple = [relayingType: bigint, deliveryPayment: bigint];
  export interface OutputObject {
    relayingType: bigint;
    deliveryPayment: bigint;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace SendTransceiverMessageEvent {
  export type InputTuple = [
    recipientChain: BigNumberish,
    message: TransceiverStructs.TransceiverMessageStruct
  ];
  export type OutputTuple = [
    recipientChain: bigint,
    message: TransceiverStructs.TransceiverMessageStructOutput
  ];
  export interface OutputObject {
    recipientChain: bigint;
    message: TransceiverStructs.TransceiverMessageStructOutput;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace SetIsSpecialRelayingEnabledEvent {
  export type InputTuple = [chainId: BigNumberish, isRelayingEnabled: boolean];
  export type OutputTuple = [chainId: bigint, isRelayingEnabled: boolean];
  export interface OutputObject {
    chainId: bigint;
    isRelayingEnabled: boolean;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace SetIsWormholeEvmChainEvent {
  export type InputTuple = [chainId: BigNumberish, isEvm: boolean];
  export type OutputTuple = [chainId: bigint, isEvm: boolean];
  export interface OutputObject {
    chainId: bigint;
    isEvm: boolean;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace SetIsWormholeRelayingEnabledEvent {
  export type InputTuple = [chainId: BigNumberish, isRelayingEnabled: boolean];
  export type OutputTuple = [chainId: bigint, isRelayingEnabled: boolean];
  export interface OutputObject {
    chainId: bigint;
    isRelayingEnabled: boolean;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace SetWormholePeerEvent {
  export type InputTuple = [chainId: BigNumberish, peerContract: BytesLike];
  export type OutputTuple = [chainId: bigint, peerContract: string];
  export interface OutputObject {
    chainId: bigint;
    peerContract: string;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export namespace UpgradedEvent {
  export type InputTuple = [implementation: AddressLike];
  export type OutputTuple = [implementation: string];
  export interface OutputObject {
    implementation: string;
  }
  export type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
  export type Filter = TypedDeferredTopicFilter<Event>;
  export type Log = TypedEventLog<Event>;
  export type LogDescription = TypedLogDescription<Event>;
}

export interface WormholeTransceiver extends BaseContract {
  connect(runner?: ContractRunner | null): WormholeTransceiver;
  waitForDeployment(): Promise<this>;

  interface: WormholeTransceiverInterface;

  queryFilter<TCEvent extends TypedContractEvent>(
    event: TCEvent,
    fromBlockOrBlockhash?: string | number | undefined,
    toBlock?: string | number | undefined
  ): Promise<Array<TypedEventLog<TCEvent>>>;
  queryFilter<TCEvent extends TypedContractEvent>(
    filter: TypedDeferredTopicFilter<TCEvent>,
    fromBlockOrBlockhash?: string | number | undefined,
    toBlock?: string | number | undefined
  ): Promise<Array<TypedEventLog<TCEvent>>>;

  on<TCEvent extends TypedContractEvent>(
    event: TCEvent,
    listener: TypedListener<TCEvent>
  ): Promise<this>;
  on<TCEvent extends TypedContractEvent>(
    filter: TypedDeferredTopicFilter<TCEvent>,
    listener: TypedListener<TCEvent>
  ): Promise<this>;

  once<TCEvent extends TypedContractEvent>(
    event: TCEvent,
    listener: TypedListener<TCEvent>
  ): Promise<this>;
  once<TCEvent extends TypedContractEvent>(
    filter: TypedDeferredTopicFilter<TCEvent>,
    listener: TypedListener<TCEvent>
  ): Promise<this>;

  listeners<TCEvent extends TypedContractEvent>(
    event: TCEvent
  ): Promise<Array<TypedListener<TCEvent>>>;
  listeners(eventName?: string): Promise<Array<Listener>>;
  removeAllListeners<TCEvent extends TypedContractEvent>(
    event?: TCEvent
  ): Promise<this>;

  consistencyLevel: TypedContractMethod<[], [bigint], "view">;

  encodeWormholeTransceiverInstruction: TypedContractMethod<
    [instruction: IWormholeTransceiver.WormholeTransceiverInstructionStruct],
    [string],
    "view"
  >;

  gasLimit: TypedContractMethod<[], [bigint], "view">;

  getMigratesImmutables: TypedContractMethod<[], [boolean], "view">;

  getNttManagerOwner: TypedContractMethod<[], [string], "view">;

  getNttManagerToken: TypedContractMethod<[], [string], "view">;

  getWormholePeer: TypedContractMethod<
    [chainId: BigNumberish],
    [string],
    "view"
  >;

  initialize: TypedContractMethod<[], [void], "nonpayable">;

  isPaused: TypedContractMethod<[], [boolean], "view">;

  isSpecialRelayingEnabled: TypedContractMethod<
    [chainId: BigNumberish],
    [boolean],
    "view"
  >;

  isVAAConsumed: TypedContractMethod<[hash: BytesLike], [boolean], "view">;

  isWormholeEvmChain: TypedContractMethod<
    [chainId: BigNumberish],
    [boolean],
    "view"
  >;

  isWormholeRelayingEnabled: TypedContractMethod<
    [chainId: BigNumberish],
    [boolean],
    "view"
  >;

  migrate: TypedContractMethod<[], [void], "nonpayable">;

  nttManager: TypedContractMethod<[], [string], "view">;

  nttManagerToken: TypedContractMethod<[], [string], "view">;

  owner: TypedContractMethod<[], [string], "view">;

  parseWormholeTransceiverInstruction: TypedContractMethod<
    [encoded: BytesLike],
    [IWormholeTransceiver.WormholeTransceiverInstructionStructOutput],
    "view"
  >;

  pauser: TypedContractMethod<[], [string], "view">;

  quoteDeliveryPrice: TypedContractMethod<
    [
      targetChain: BigNumberish,
      instruction: TransceiverStructs.TransceiverInstructionStruct
    ],
    [bigint],
    "view"
  >;

  receiveMessage: TypedContractMethod<
    [encodedMessage: BytesLike],
    [void],
    "nonpayable"
  >;

  receiveWormholeMessages: TypedContractMethod<
    [
      payload: BytesLike,
      additionalMessages: BytesLike[],
      sourceAddress: BytesLike,
      sourceChain: BigNumberish,
      deliveryHash: BytesLike
    ],
    [void],
    "payable"
  >;

  sendMessage: TypedContractMethod<
    [
      recipientChain: BigNumberish,
      instruction: TransceiverStructs.TransceiverInstructionStruct,
      nttManagerMessage: BytesLike,
      recipientNttManagerAddress: BytesLike
    ],
    [void],
    "payable"
  >;

  setIsSpecialRelayingEnabled: TypedContractMethod<
    [chainId: BigNumberish, isEnabled: boolean],
    [void],
    "nonpayable"
  >;

  setIsWormholeEvmChain: TypedContractMethod<
    [chainId: BigNumberish, isEvm: boolean],
    [void],
    "nonpayable"
  >;

  setIsWormholeRelayingEnabled: TypedContractMethod<
    [chainId: BigNumberish, isEnabled: boolean],
    [void],
    "nonpayable"
  >;

  setWormholePeer: TypedContractMethod<
    [peerChainId: BigNumberish, peerContract: BytesLike],
    [void],
    "nonpayable"
  >;

  specialRelayer: TypedContractMethod<[], [string], "view">;

  transferOwnership: TypedContractMethod<
    [newOwner: AddressLike],
    [void],
    "nonpayable"
  >;

  transferPauserCapability: TypedContractMethod<
    [newPauser: AddressLike],
    [void],
    "nonpayable"
  >;

  transferTransceiverOwnership: TypedContractMethod<
    [newOwner: AddressLike],
    [void],
    "nonpayable"
  >;

  upgrade: TypedContractMethod<
    [newImplementation: AddressLike],
    [void],
    "nonpayable"
  >;

  wormhole: TypedContractMethod<[], [string], "view">;

  wormholeRelayer: TypedContractMethod<[], [string], "view">;

  getFunction<T extends ContractMethod = ContractMethod>(
    key: string | FunctionFragment
  ): T;

  getFunction(
    nameOrSignature: "consistencyLevel"
  ): TypedContractMethod<[], [bigint], "view">;
  getFunction(
    nameOrSignature: "encodeWormholeTransceiverInstruction"
  ): TypedContractMethod<
    [instruction: IWormholeTransceiver.WormholeTransceiverInstructionStruct],
    [string],
    "view"
  >;
  getFunction(
    nameOrSignature: "gasLimit"
  ): TypedContractMethod<[], [bigint], "view">;
  getFunction(
    nameOrSignature: "getMigratesImmutables"
  ): TypedContractMethod<[], [boolean], "view">;
  getFunction(
    nameOrSignature: "getNttManagerOwner"
  ): TypedContractMethod<[], [string], "view">;
  getFunction(
    nameOrSignature: "getNttManagerToken"
  ): TypedContractMethod<[], [string], "view">;
  getFunction(
    nameOrSignature: "getWormholePeer"
  ): TypedContractMethod<[chainId: BigNumberish], [string], "view">;
  getFunction(
    nameOrSignature: "initialize"
  ): TypedContractMethod<[], [void], "nonpayable">;
  getFunction(
    nameOrSignature: "isPaused"
  ): TypedContractMethod<[], [boolean], "view">;
  getFunction(
    nameOrSignature: "isSpecialRelayingEnabled"
  ): TypedContractMethod<[chainId: BigNumberish], [boolean], "view">;
  getFunction(
    nameOrSignature: "isVAAConsumed"
  ): TypedContractMethod<[hash: BytesLike], [boolean], "view">;
  getFunction(
    nameOrSignature: "isWormholeEvmChain"
  ): TypedContractMethod<[chainId: BigNumberish], [boolean], "view">;
  getFunction(
    nameOrSignature: "isWormholeRelayingEnabled"
  ): TypedContractMethod<[chainId: BigNumberish], [boolean], "view">;
  getFunction(
    nameOrSignature: "migrate"
  ): TypedContractMethod<[], [void], "nonpayable">;
  getFunction(
    nameOrSignature: "nttManager"
  ): TypedContractMethod<[], [string], "view">;
  getFunction(
    nameOrSignature: "nttManagerToken"
  ): TypedContractMethod<[], [string], "view">;
  getFunction(
    nameOrSignature: "owner"
  ): TypedContractMethod<[], [string], "view">;
  getFunction(
    nameOrSignature: "parseWormholeTransceiverInstruction"
  ): TypedContractMethod<
    [encoded: BytesLike],
    [IWormholeTransceiver.WormholeTransceiverInstructionStructOutput],
    "view"
  >;
  getFunction(
    nameOrSignature: "pauser"
  ): TypedContractMethod<[], [string], "view">;
  getFunction(
    nameOrSignature: "quoteDeliveryPrice"
  ): TypedContractMethod<
    [
      targetChain: BigNumberish,
      instruction: TransceiverStructs.TransceiverInstructionStruct
    ],
    [bigint],
    "view"
  >;
  getFunction(
    nameOrSignature: "receiveMessage"
  ): TypedContractMethod<[encodedMessage: BytesLike], [void], "nonpayable">;
  getFunction(
    nameOrSignature: "receiveWormholeMessages"
  ): TypedContractMethod<
    [
      payload: BytesLike,
      additionalMessages: BytesLike[],
      sourceAddress: BytesLike,
      sourceChain: BigNumberish,
      deliveryHash: BytesLike
    ],
    [void],
    "payable"
  >;
  getFunction(
    nameOrSignature: "sendMessage"
  ): TypedContractMethod<
    [
      recipientChain: BigNumberish,
      instruction: TransceiverStructs.TransceiverInstructionStruct,
      nttManagerMessage: BytesLike,
      recipientNttManagerAddress: BytesLike
    ],
    [void],
    "payable"
  >;
  getFunction(
    nameOrSignature: "setIsSpecialRelayingEnabled"
  ): TypedContractMethod<
    [chainId: BigNumberish, isEnabled: boolean],
    [void],
    "nonpayable"
  >;
  getFunction(
    nameOrSignature: "setIsWormholeEvmChain"
  ): TypedContractMethod<
    [chainId: BigNumberish, isEvm: boolean],
    [void],
    "nonpayable"
  >;
  getFunction(
    nameOrSignature: "setIsWormholeRelayingEnabled"
  ): TypedContractMethod<
    [chainId: BigNumberish, isEnabled: boolean],
    [void],
    "nonpayable"
  >;
  getFunction(
    nameOrSignature: "setWormholePeer"
  ): TypedContractMethod<
    [peerChainId: BigNumberish, peerContract: BytesLike],
    [void],
    "nonpayable"
  >;
  getFunction(
    nameOrSignature: "specialRelayer"
  ): TypedContractMethod<[], [string], "view">;
  getFunction(
    nameOrSignature: "transferOwnership"
  ): TypedContractMethod<[newOwner: AddressLike], [void], "nonpayable">;
  getFunction(
    nameOrSignature: "transferPauserCapability"
  ): TypedContractMethod<[newPauser: AddressLike], [void], "nonpayable">;
  getFunction(
    nameOrSignature: "transferTransceiverOwnership"
  ): TypedContractMethod<[newOwner: AddressLike], [void], "nonpayable">;
  getFunction(
    nameOrSignature: "upgrade"
  ): TypedContractMethod<
    [newImplementation: AddressLike],
    [void],
    "nonpayable"
  >;
  getFunction(
    nameOrSignature: "wormhole"
  ): TypedContractMethod<[], [string], "view">;
  getFunction(
    nameOrSignature: "wormholeRelayer"
  ): TypedContractMethod<[], [string], "view">;

  getEvent(
    key: "AdminChanged"
  ): TypedContractEvent<
    AdminChangedEvent.InputTuple,
    AdminChangedEvent.OutputTuple,
    AdminChangedEvent.OutputObject
  >;
  getEvent(
    key: "BeaconUpgraded"
  ): TypedContractEvent<
    BeaconUpgradedEvent.InputTuple,
    BeaconUpgradedEvent.OutputTuple,
    BeaconUpgradedEvent.OutputObject
  >;
  getEvent(
    key: "Initialized"
  ): TypedContractEvent<
    InitializedEvent.InputTuple,
    InitializedEvent.OutputTuple,
    InitializedEvent.OutputObject
  >;
  getEvent(
    key: "NotPaused"
  ): TypedContractEvent<
    NotPausedEvent.InputTuple,
    NotPausedEvent.OutputTuple,
    NotPausedEvent.OutputObject
  >;
  getEvent(
    key: "OwnershipTransferred"
  ): TypedContractEvent<
    OwnershipTransferredEvent.InputTuple,
    OwnershipTransferredEvent.OutputTuple,
    OwnershipTransferredEvent.OutputObject
  >;
  getEvent(
    key: "Paused"
  ): TypedContractEvent<
    PausedEvent.InputTuple,
    PausedEvent.OutputTuple,
    PausedEvent.OutputObject
  >;
  getEvent(
    key: "PauserTransferred"
  ): TypedContractEvent<
    PauserTransferredEvent.InputTuple,
    PauserTransferredEvent.OutputTuple,
    PauserTransferredEvent.OutputObject
  >;
  getEvent(
    key: "ReceivedMessage"
  ): TypedContractEvent<
    ReceivedMessageEvent.InputTuple,
    ReceivedMessageEvent.OutputTuple,
    ReceivedMessageEvent.OutputObject
  >;
  getEvent(
    key: "ReceivedRelayedMessage"
  ): TypedContractEvent<
    ReceivedRelayedMessageEvent.InputTuple,
    ReceivedRelayedMessageEvent.OutputTuple,
    ReceivedRelayedMessageEvent.OutputObject
  >;
  getEvent(
    key: "RelayingInfo"
  ): TypedContractEvent<
    RelayingInfoEvent.InputTuple,
    RelayingInfoEvent.OutputTuple,
    RelayingInfoEvent.OutputObject
  >;
  getEvent(
    key: "SendTransceiverMessage"
  ): TypedContractEvent<
    SendTransceiverMessageEvent.InputTuple,
    SendTransceiverMessageEvent.OutputTuple,
    SendTransceiverMessageEvent.OutputObject
  >;
  getEvent(
    key: "SetIsSpecialRelayingEnabled"
  ): TypedContractEvent<
    SetIsSpecialRelayingEnabledEvent.InputTuple,
    SetIsSpecialRelayingEnabledEvent.OutputTuple,
    SetIsSpecialRelayingEnabledEvent.OutputObject
  >;
  getEvent(
    key: "SetIsWormholeEvmChain"
  ): TypedContractEvent<
    SetIsWormholeEvmChainEvent.InputTuple,
    SetIsWormholeEvmChainEvent.OutputTuple,
    SetIsWormholeEvmChainEvent.OutputObject
  >;
  getEvent(
    key: "SetIsWormholeRelayingEnabled"
  ): TypedContractEvent<
    SetIsWormholeRelayingEnabledEvent.InputTuple,
    SetIsWormholeRelayingEnabledEvent.OutputTuple,
    SetIsWormholeRelayingEnabledEvent.OutputObject
  >;
  getEvent(
    key: "SetWormholePeer"
  ): TypedContractEvent<
    SetWormholePeerEvent.InputTuple,
    SetWormholePeerEvent.OutputTuple,
    SetWormholePeerEvent.OutputObject
  >;
  getEvent(
    key: "Upgraded"
  ): TypedContractEvent<
    UpgradedEvent.InputTuple,
    UpgradedEvent.OutputTuple,
    UpgradedEvent.OutputObject
  >;

  filters: {
    "AdminChanged(address,address)": TypedContractEvent<
      AdminChangedEvent.InputTuple,
      AdminChangedEvent.OutputTuple,
      AdminChangedEvent.OutputObject
    >;
    AdminChanged: TypedContractEvent<
      AdminChangedEvent.InputTuple,
      AdminChangedEvent.OutputTuple,
      AdminChangedEvent.OutputObject
    >;

    "BeaconUpgraded(address)": TypedContractEvent<
      BeaconUpgradedEvent.InputTuple,
      BeaconUpgradedEvent.OutputTuple,
      BeaconUpgradedEvent.OutputObject
    >;
    BeaconUpgraded: TypedContractEvent<
      BeaconUpgradedEvent.InputTuple,
      BeaconUpgradedEvent.OutputTuple,
      BeaconUpgradedEvent.OutputObject
    >;

    "Initialized(uint64)": TypedContractEvent<
      InitializedEvent.InputTuple,
      InitializedEvent.OutputTuple,
      InitializedEvent.OutputObject
    >;
    Initialized: TypedContractEvent<
      InitializedEvent.InputTuple,
      InitializedEvent.OutputTuple,
      InitializedEvent.OutputObject
    >;

    "NotPaused(bool)": TypedContractEvent<
      NotPausedEvent.InputTuple,
      NotPausedEvent.OutputTuple,
      NotPausedEvent.OutputObject
    >;
    NotPaused: TypedContractEvent<
      NotPausedEvent.InputTuple,
      NotPausedEvent.OutputTuple,
      NotPausedEvent.OutputObject
    >;

    "OwnershipTransferred(address,address)": TypedContractEvent<
      OwnershipTransferredEvent.InputTuple,
      OwnershipTransferredEvent.OutputTuple,
      OwnershipTransferredEvent.OutputObject
    >;
    OwnershipTransferred: TypedContractEvent<
      OwnershipTransferredEvent.InputTuple,
      OwnershipTransferredEvent.OutputTuple,
      OwnershipTransferredEvent.OutputObject
    >;

    "Paused(bool)": TypedContractEvent<
      PausedEvent.InputTuple,
      PausedEvent.OutputTuple,
      PausedEvent.OutputObject
    >;
    Paused: TypedContractEvent<
      PausedEvent.InputTuple,
      PausedEvent.OutputTuple,
      PausedEvent.OutputObject
    >;

    "PauserTransferred(address,address)": TypedContractEvent<
      PauserTransferredEvent.InputTuple,
      PauserTransferredEvent.OutputTuple,
      PauserTransferredEvent.OutputObject
    >;
    PauserTransferred: TypedContractEvent<
      PauserTransferredEvent.InputTuple,
      PauserTransferredEvent.OutputTuple,
      PauserTransferredEvent.OutputObject
    >;

    "ReceivedMessage(bytes32,uint16,bytes32,uint64)": TypedContractEvent<
      ReceivedMessageEvent.InputTuple,
      ReceivedMessageEvent.OutputTuple,
      ReceivedMessageEvent.OutputObject
    >;
    ReceivedMessage: TypedContractEvent<
      ReceivedMessageEvent.InputTuple,
      ReceivedMessageEvent.OutputTuple,
      ReceivedMessageEvent.OutputObject
    >;

    "ReceivedRelayedMessage(bytes32,uint16,bytes32)": TypedContractEvent<
      ReceivedRelayedMessageEvent.InputTuple,
      ReceivedRelayedMessageEvent.OutputTuple,
      ReceivedRelayedMessageEvent.OutputObject
    >;
    ReceivedRelayedMessage: TypedContractEvent<
      ReceivedRelayedMessageEvent.InputTuple,
      ReceivedRelayedMessageEvent.OutputTuple,
      ReceivedRelayedMessageEvent.OutputObject
    >;

    "RelayingInfo(uint8,uint256)": TypedContractEvent<
      RelayingInfoEvent.InputTuple,
      RelayingInfoEvent.OutputTuple,
      RelayingInfoEvent.OutputObject
    >;
    RelayingInfo: TypedContractEvent<
      RelayingInfoEvent.InputTuple,
      RelayingInfoEvent.OutputTuple,
      RelayingInfoEvent.OutputObject
    >;

    "SendTransceiverMessage(uint16,tuple)": TypedContractEvent<
      SendTransceiverMessageEvent.InputTuple,
      SendTransceiverMessageEvent.OutputTuple,
      SendTransceiverMessageEvent.OutputObject
    >;
    SendTransceiverMessage: TypedContractEvent<
      SendTransceiverMessageEvent.InputTuple,
      SendTransceiverMessageEvent.OutputTuple,
      SendTransceiverMessageEvent.OutputObject
    >;

    "SetIsSpecialRelayingEnabled(uint16,bool)": TypedContractEvent<
      SetIsSpecialRelayingEnabledEvent.InputTuple,
      SetIsSpecialRelayingEnabledEvent.OutputTuple,
      SetIsSpecialRelayingEnabledEvent.OutputObject
    >;
    SetIsSpecialRelayingEnabled: TypedContractEvent<
      SetIsSpecialRelayingEnabledEvent.InputTuple,
      SetIsSpecialRelayingEnabledEvent.OutputTuple,
      SetIsSpecialRelayingEnabledEvent.OutputObject
    >;

    "SetIsWormholeEvmChain(uint16,bool)": TypedContractEvent<
      SetIsWormholeEvmChainEvent.InputTuple,
      SetIsWormholeEvmChainEvent.OutputTuple,
      SetIsWormholeEvmChainEvent.OutputObject
    >;
    SetIsWormholeEvmChain: TypedContractEvent<
      SetIsWormholeEvmChainEvent.InputTuple,
      SetIsWormholeEvmChainEvent.OutputTuple,
      SetIsWormholeEvmChainEvent.OutputObject
    >;

    "SetIsWormholeRelayingEnabled(uint16,bool)": TypedContractEvent<
      SetIsWormholeRelayingEnabledEvent.InputTuple,
      SetIsWormholeRelayingEnabledEvent.OutputTuple,
      SetIsWormholeRelayingEnabledEvent.OutputObject
    >;
    SetIsWormholeRelayingEnabled: TypedContractEvent<
      SetIsWormholeRelayingEnabledEvent.InputTuple,
      SetIsWormholeRelayingEnabledEvent.OutputTuple,
      SetIsWormholeRelayingEnabledEvent.OutputObject
    >;

    "SetWormholePeer(uint16,bytes32)": TypedContractEvent<
      SetWormholePeerEvent.InputTuple,
      SetWormholePeerEvent.OutputTuple,
      SetWormholePeerEvent.OutputObject
    >;
    SetWormholePeer: TypedContractEvent<
      SetWormholePeerEvent.InputTuple,
      SetWormholePeerEvent.OutputTuple,
      SetWormholePeerEvent.OutputObject
    >;

    "Upgraded(address)": TypedContractEvent<
      UpgradedEvent.InputTuple,
      UpgradedEvent.OutputTuple,
      UpgradedEvent.OutputObject
    >;
    Upgraded: TypedContractEvent<
      UpgradedEvent.InputTuple,
      UpgradedEvent.OutputTuple,
      UpgradedEvent.OutputObject
    >;
  };
}

import {
  encoding,
  serializeLayout,
  toChainId,
  type Chain,
  type Network,
} from "@wormhole-foundation/sdk-base";

import {
  AccountAddress,
  ChainAddress,
  EmptyPlatformMap,
  ProtocolPayload,
  ProtocolVAA,
  TokenAddress,
  UnsignedTransaction,
  keccak256,
} from "@wormhole-foundation/sdk-definitions";

import {
  NttManagerMessage,
  nativeTokenTransferLayout,
  nttManagerMessageLayout,
  transceiverInfo,
  transceiverInstructionLayout,
  transceiverRegistration,
} from "./layouts/index.js";

/**
 * @namespace Ntt
 */
export namespace Ntt {
  const _protocol = "Ntt";
  export type ProtocolName = typeof _protocol;

  export type Mode = "locking" | "burning";
  export type Contracts = {
    token: string;
    manager: string;
    transceiver: {
      wormhole: string;
    };
    quoter?: string;
  };

  export type Message = NttManagerMessage<typeof nativeTokenTransferLayout>;

  export type TransceiverInfo = NttManagerMessage<typeof transceiverInfo>;
  export type TransceiverRegistration = NttManagerMessage<
    typeof transceiverRegistration
  >;

  export type TransferOptions = {
    /** Whether or not to queue the transfer if the outbound capacity is exceeded */
    queue: boolean;
    /** Whether or not to request this transfer should be relayed, otherwise manual redemption is required */
    automatic?: boolean;
    /** How much native gas on the destination to send along with the transfer */
    gasDropoff?: bigint;
  };

  // TODO: what are the set of attestation types for Ntt?
  // can we know this ahead of time or does it need to be
  // flexible enough for folks to add their own somehow?
  export type Attestation = any;

  /**
   * InboundQueuedTransfer is a queued transfer from another chain
   * @property recipient the recipient of the transfer
   * @property amount the amount of the transfer
   * @property rateLimitExpiryTimestamp the timestamp when the rate limit expires
   */
  export type InboundQueuedTransfer<C extends Chain> = {
    recipient: AccountAddress<C>;
    amount: bigint;
    rateLimitExpiryTimestamp: number;
  };
  /**
   * TransceiverInstruction is a single instruction for the transceiver
   * @property index the index of the instruction, may not be > 255
   * @property payload the payload of the instruction, may not exceed 255 bytes
   */
  export type TransceiverInstruction = {
    index: number;
    payload: Uint8Array;
  };

  // TODO: should layoutify this but couldnt immediately figure out how to
  // specify the length of the array as an encoded value
  export function encodeTransceiverInstructions(ixs: TransceiverInstruction[]) {
    if (ixs.length > 255)
      throw new Error(`Too many instructions (${ixs.length})`);
    return encoding.bytes.concat(
      new Uint8Array([ixs.length]),
      ...ixs.map((ix) => serializeLayout(transceiverInstructionLayout(), ix))
    );
  }

  /**
   * messageDigest hashes a message for the Ntt manager, the digest is used
   * to uniquely identify the message
   * @param chain The chain that sent the message
   * @param message The ntt message to hash
   * @returns a 32 byte digest of the message
   */
  export function messageDigest(chain: Chain, message: Message): Uint8Array {
    return keccak256(
      encoding.bytes.concat(
        encoding.bignum.toBytes(toChainId(chain), 2),
        serializeLayout(
          nttManagerMessageLayout(nativeTokenTransferLayout),
          message
        )
      )
    );
  }
}

/**
 * Ntt is the interface for the Ntt
 *
 * The Ntt is responsible for managing the coordination between the token contract and
 * the transceiver(s). It is also responsible for managing the capacity of inbound or outbount transfers.
 *
 * @typeparam N the network
 * @typeparam C the chain
 */
export interface Ntt<N extends Network, C extends Chain> {
  setPeer(
    peer: ChainAddress,
    tokenDecimals: number,
    inboundLimit: bigint,
    payer?: AccountAddress<C>
  ): AsyncGenerator<UnsignedTransaction<N, C>>;
  setWormholeTransceiverPeer(
    peer: ChainAddress,
    payer?: AccountAddress<C>
  ): AsyncGenerator<UnsignedTransaction<N, C>>;

  /**
   * quoteDeliveryPrice returns the price to deliver a message to a given chain
   * the price is quote in native gas
   *
   * @param destination the destination chain
   * @param flags the flags to use for the delivery
   */
  quoteDeliveryPrice(
    destination: Chain,
    options: Ntt.TransferOptions
  ): Promise<bigint>;

  /**
   * transfer sends a message to the Ntt manager to initiate a transfer
   * @param sender the address of the sender
   * @param amount the amount to transfer
   * @param destination the destination chain
   * @param queue whether to queue the transfer if the outbound capacity is exceeded
   * @param relay whether to relay the transfer
   */
  transfer(
    sender: AccountAddress<C>,
    amount: bigint,
    destination: ChainAddress,
    options: Ntt.TransferOptions
  ): AsyncGenerator<UnsignedTransaction<N, C>>;

  /**
   * redeem redeems a set of Attestations to the corresponding transceivers on the destination chain
   * @param attestations The attestations to redeem, the length should be equal to the number of transceivers
   */
  redeem(
    attestations: Ntt.Attestation[],
    payer?: AccountAddress<C>
  ): AsyncGenerator<UnsignedTransaction<N, C>>;

  /** Get the interface version */
  getVersion(payer?: AccountAddress<C>): Promise<string>;

  /** Get the address for the account that custodies locked tokens  */
  getCustodyAddress(): Promise<string>;

  /** Get the number of decimals associated with the token under management */
  getTokenDecimals(): Promise<number>;

  /**
   * getCurrentOutboundCapacity returns the current outbound capacity of the Ntt manager
   */
  getCurrentOutboundCapacity(): Promise<bigint>;
  /**
   * getCurrentInboundCapacity returns the current inbound capacity of the Ntt manager
   * @param fromChain the chain to check the inbound capacity for
   */
  getCurrentInboundCapacity(fromChain: Chain): Promise<bigint>;

  /**
   * getIsApproved returns whether an attestation is approved
   * an attestation is approved when it has been validated but has not necessarily
   * been executed
   *
   * @param attestation the attestation to check
   */
  getIsApproved(attestation: Ntt.Attestation): Promise<boolean>;

  /**
   * getIsExecuted returns whether an attestation is executed
   * an attestation being executed means the transfer is complete
   *
   * @param attestation the attestation to check
   */
  getIsExecuted(attestation: Ntt.Attestation): Promise<boolean>;

  /**
   * getInboundQueuedTransfer returns the details of an inbound queued transfer
   * @param transceiverMessage the transceiver message
   * @param fromChain the chain the transfer is from
   */
  getInboundQueuedTransfer(
    fromChain: Chain,
    transceiverMessage: Ntt.Message
  ): Promise<Ntt.InboundQueuedTransfer<C> | null>;
  /**
   * completeInboundQueuedTransfer completes an inbound queued transfer
   * @param transceiverMessage the transceiver message
   * @param token the token to transfer
   * @param fromChain the chain the transfer is from
   * @param payer the address to pay for the transfer
   */
  completeInboundQueuedTransfer(
    fromChain: Chain,
    transceiverMessage: Ntt.Message,
    token: TokenAddress<C>,
    payer?: AccountAddress<C>
  ): AsyncGenerator<UnsignedTransaction<N, C>>;
}

export interface NttTransceiver<
  N extends Network,
  C extends Chain,
  A extends Ntt.Attestation
> {
  /** setPeer sets a peer address for a given chain
   * Note: Admin only
   */
  setPeer(peer: ChainAddress<Chain>): AsyncGenerator<UnsignedTransaction<N, C>>;

  /**
   * receive calls the `receive*` method on the transceiver
   *
   * @param attestation the attestation to redeem against the transceiver
   * @param sender the address of the sender
   */
  receive(
    attestation: A,
    sender?: AccountAddress<C>
  ): AsyncGenerator<UnsignedTransaction<N, C>>;
}

export namespace WormholeNttTransceiver {
  const _payloads = ["WormholeTransfer"] as const;
  export type PayloadNames = (typeof _payloads)[number];
  export type VAA<PayloadName extends PayloadNames = PayloadNames> =
    ProtocolVAA<Ntt.ProtocolName, PayloadName>;
  export type Payload<PayloadName extends PayloadNames = PayloadNames> =
    ProtocolPayload<Ntt.ProtocolName, PayloadName>;
}

/**
 * WormholeNttTransceiver is the interface for the Wormhole Ntt transceiver
 *
 * The WormholeNttTransceiver is responsible for verifying VAAs against the core
 * bridge and signaling the NttManager that it can mint tokens.
 */
export interface WormholeNttTransceiver<N extends Network, C extends Chain>
  extends NttTransceiver<N, C, WormholeNttTransceiver.VAA> {}

declare module "@wormhole-foundation/sdk-definitions" {
  export namespace WormholeRegistry {
    interface ProtocolToInterfaceMapping<N, C> {
      Ntt: Ntt<N, C>;
    }
    interface ProtocolToPlatformMapping {
      Ntt: EmptyPlatformMap<Ntt.ProtocolName>;
    }
  }
}

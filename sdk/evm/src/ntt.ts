import {
  AccountAddress,
  Chain,
  ChainAddress,
  ChainsConfig,
  Contracts,
  Network,
  TokenAddress,
  nativeChainIds,
  serialize,
  toChainId,
  universalAddress,
} from "@wormhole-foundation/sdk-connect";
import type { EvmChains, EvmPlatformType } from "@wormhole-foundation/sdk-evm";
import {
  EvmAddress,
  EvmPlatform,
  EvmUnsignedTransaction,
  addChainId,
  addFrom,
} from "@wormhole-foundation/sdk-evm";
import "@wormhole-foundation/sdk-evm-core";

import {
  Ntt,
  NttTransceiver,
  WormholeNttTransceiver,
} from "@wormhole-foundation/sdk-definitions-ntt";
import type { Provider, TransactionRequest } from "ethers";
import { ethers_contracts } from "./index.js";

export class EvmNttWormholeTranceiver<N extends Network, C extends EvmChains>
  implements NttTransceiver<N, C, WormholeNttTransceiver.VAA>
{
  transceiver: ethers_contracts.WormholeTransceiver;
  constructor(readonly manager: EvmNtt<N, C>, readonly address: string) {
    this.transceiver =
      ethers_contracts.factories.WormholeTransceiver__factory.connect(
        address,
        manager.provider
      );
  }

  encodeFlags(skipRelay: boolean): Uint8Array {
    return new Uint8Array([skipRelay ? 1 : 0]);
  }

  async *setPeer(peer: ChainAddress<C>) {
    const tx = await this.transceiver.setWormholePeer.populateTransaction(
      toChainId(peer.chain),
      universalAddress(peer)
    );
    yield this.manager.createUnsignedTx(tx, "WormholeTransceiver.registerPeer");
  }
  async *receive(attestation: WormholeNttTransceiver.VAA) {
    const tx = await this.transceiver.receiveMessage.populateTransaction(
      serialize(attestation)
    );
    yield this.manager.createUnsignedTx(
      tx,
      "WormholeTransceiver.receiveMessage"
    );
  }

  async isWormholeRelayingEnabled(destChain: Chain): Promise<boolean> {
    return await this.transceiver.isWormholeRelayingEnabled(
      toChainId(destChain)
    );
  }

  async isSpecialRelayingEnabled(destChain: Chain): Promise<boolean> {
    return await this.transceiver.isSpecialRelayingEnabled(
      toChainId(destChain)
    );
  }
}

export class EvmNtt<N extends Network, C extends EvmChains>
  implements Ntt<N, C>
{
  tokenAddress: string;
  readonly chainId: bigint;
  manager: ethers_contracts.NttManager;
  xcvrs: EvmNttWormholeTranceiver<N, C>[];
  managerAddress: string;

  constructor(
    readonly network: N,
    readonly chain: C,
    readonly provider: Provider,
    readonly contracts: Contracts & { ntt?: Ntt.Contracts }
  ) {
    if (!contracts.ntt) throw new Error("No Ntt Contracts provided");

    this.chainId = nativeChainIds.networkChainToNativeChainId.get(
      network,
      chain
    ) as bigint;

    this.tokenAddress = contracts.ntt.token;
    this.managerAddress = contracts.ntt.manager;
    this.manager = ethers_contracts.factories.NttManager__factory.connect(
      contracts.ntt.manager,
      this.provider
    );

    this.xcvrs = [
      // Enable more Transceivers here
      new EvmNttWormholeTranceiver(this, contracts.ntt.transceiver.wormhole!),
    ];
  }

  static async fromRpc<N extends Network>(
    provider: Provider,
    config: ChainsConfig<N, EvmPlatformType>
  ): Promise<EvmNtt<N, EvmChains>> {
    throw "Not Implemented";
    // TODO
    // const [network, chain] = await EvmPlatform.chainFromRpc(provider);
    // return new EvmNtt(network, chain, provider, {} as Ntt.Contracts) as EvmNtt<
    //   N,
    //   EvmChains
    // >;
  }

  private encodeFlags(enabledIdxs?: number[]): Ntt.TransceiverInstruction[] {
    return this.xcvrs
      .map((xcvr, idx) => {
        if (!enabledIdxs || enabledIdxs.includes(idx))
          return { index: idx, payload: xcvr.encodeFlags(true) };
        return null;
      })
      .filter((x) => x !== null) as Ntt.TransceiverInstruction[];
  }

  async getCustodyAddress() {
    return this.managerAddress;
  }

  async quoteDeliveryPrice(dstChain: Chain): Promise<[bigint[], bigint]> {
    return this.manager.quoteDeliveryPrice.staticCall(
      toChainId(dstChain),
      Ntt.encodeTransceiverInstructions(this.encodeFlags())
    );
  }

  async *setPeer(
    peer: ChainAddress<C>,
    tokenDecimals: number,
    inboundLimit: bigint
  ) {
    const tx = await this.manager.setPeer.populateTransaction(
      toChainId(peer.chain),
      universalAddress(peer),
      tokenDecimals,
      inboundLimit
    );
    yield this.createUnsignedTx(tx, "Ntt.setPeer");
  }

  async *setWormholeTransceiverPeer(peer: ChainAddress<C>) {
    // TODO: we only have one right now, so just set the peer on that one
    yield* this.xcvrs[0]!.setPeer(peer);
  }

  async *transfer(
    sender: AccountAddress<C>,
    amount: bigint,
    destination: ChainAddress,
    queue: boolean
  ): AsyncGenerator<EvmUnsignedTransaction<N, C>> {
    const [_, totalPrice] = await this.quoteDeliveryPrice(destination.chain);
    const transceiverIxs = Ntt.encodeTransceiverInstructions(
      this.encodeFlags()
    );
    const senderAddress = new EvmAddress(sender).toString();

    //TODO check for ERC-2612 (permit) support on token?
    const tokenContract = EvmPlatform.getTokenImplementation(
      this.provider,
      this.tokenAddress
    );

    const allowance = await tokenContract.allowance(
      senderAddress,
      this.managerAddress
    );
    if (allowance < amount) {
      const txReq = await tokenContract.approve.populateTransaction(
        this.managerAddress,
        amount
      );
      yield this.createUnsignedTx(
        addFrom(txReq, senderAddress),
        "TokenBridge.Approve"
      );
    }

    const txReq = await this.manager
      .getFunction("transfer(uint256,uint16,bytes32,bool,bytes)")
      .populateTransaction(
        amount,
        toChainId(destination.chain),
        universalAddress(destination),
        queue,
        transceiverIxs,
        { value: totalPrice }
      );

    yield this.createUnsignedTx(addFrom(txReq, senderAddress), "Ntt.transfer");
  }

  // TODO: should this be some map of idx to transceiver?
  async *redeem(attestations: Ntt.Attestation[]) {
    if (attestations.length !== this.xcvrs.length) throw "no";

    for (const idx in this.xcvrs) {
      const xcvr = this.xcvrs[idx]!;
      yield* xcvr.receive(attestations[idx]);
    }
  }

  async getCurrentOutboundCapacity(): Promise<bigint> {
    return await this.manager.getCurrentOutboundCapacity();
  }

  async getCurrentInboundCapacity(fromChain: Chain): Promise<bigint> {
    return await this.manager.getCurrentInboundCapacity(toChainId(fromChain));
  }

  async getRateLimitDuration(): Promise<bigint> {
    return await this.manager.rateLimitDuration();
  }

  async getInboundQueuedTransfer(
    fromChain: Chain,
    transceiverMessage: Ntt.Message
  ): Promise<Ntt.InboundQueuedTransfer<C> | null> {
    const queuedTransfer = await this.manager.getInboundQueuedTransfer(
      Ntt.messageDigest(fromChain, transceiverMessage)
    );
    if (queuedTransfer.txTimestamp > 0n) {
      const { recipient, amount, txTimestamp } = queuedTransfer;
      const duration = await this.getRateLimitDuration();
      return {
        recipient: new EvmAddress(recipient) as AccountAddress<C>,
        amount: amount,
        rateLimitExpiryTimestamp: Number(txTimestamp + duration),
      };
    }
    return null;
  }

  async *completeInboundQueuedTransfer(
    fromChain: Chain,
    transceiverMessage: Ntt.Message,
    token: TokenAddress<C>,
    payer?: AccountAddress<C>
  ) {
    const tx = await this.manager.completeInboundQueuedTransfer(
      Ntt.messageDigest(fromChain, transceiverMessage)
    );
    yield this.createUnsignedTx(tx, "Ntt.completeInboundQueuedTransfer");
  }

  createUnsignedTx(
    txReq: TransactionRequest,
    description: string,
    parallelizable: boolean = false
  ): EvmUnsignedTransaction<N, C> {
    return new EvmUnsignedTransaction(
      addChainId(txReq, this.chainId),
      this.network,
      this.chain,
      description,
      parallelizable
    );
  }
}

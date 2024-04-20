import {
  AccountAddress,
  Chain,
  ChainAddress,
  ChainsConfig,
  Contracts,
  Network,
  TokenAddress,
  VAA,
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
import { Contract, type Provider, type TransactionRequest } from "ethers";
import {
  AbiVersion,
  NttBindings,
  NttManagerBindings,
  NttTransceiverBindings,
  loadAbiVersion,
} from "./bindings.js";

export class EvmNttWormholeTranceiver<N extends Network, C extends EvmChains>
  implements NttTransceiver<N, C, WormholeNttTransceiver.VAA>
{
  transceiver: NttTransceiverBindings.NttTransceiver;
  constructor(
    readonly manager: EvmNtt<N, C>,
    readonly address: string,
    abiBindings: NttBindings
  ) {
    this.transceiver = abiBindings.NttTransceiver.connect(
      address,
      manager.provider
    );
  }

  encodeFlags(flags: { skipRelay: boolean }): Uint8Array {
    return new Uint8Array([flags.skipRelay ? 1 : 0]);
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
  manager: NttManagerBindings.NttManager;
  xcvrs: EvmNttWormholeTranceiver<N, C>[];
  managerAddress: string;

  constructor(
    readonly network: N,
    readonly chain: C,
    readonly provider: Provider,
    readonly contracts: Contracts & { ntt?: Ntt.Contracts },
    readonly abiVersion: AbiVersion = "default"
  ) {
    if (!contracts.ntt) throw new Error("No Ntt Contracts provided");

    this.chainId = nativeChainIds.networkChainToNativeChainId.get(
      network,
      chain
    ) as bigint;

    this.tokenAddress = contracts.ntt.token;
    this.managerAddress = contracts.ntt.manager;

    const abiBindings = loadAbiVersion(this.abiVersion);

    this.manager = abiBindings.NttManager.connect(
      contracts.ntt.manager,
      this.provider
    );

    this.xcvrs = [
      // Enable more Transceivers here
      new EvmNttWormholeTranceiver(
        this,
        contracts.ntt.transceiver.wormhole!,
        abiBindings!
      ),
    ];
  }

  getIsExecuted(attestation: Ntt.Attestation): Promise<boolean> {
    const { emitterChain: chain, payload } =
      attestation as VAA<"Ntt:WormholeTransfer">;
    return this.manager.isMessageExecuted(
      Ntt.messageDigest(chain, payload.nttManagerPayload)
    );
  }

  getIsApproved(attestation: Ntt.Attestation): Promise<boolean> {
    const { emitterChain: chain, payload } =
      attestation as VAA<"Ntt:WormholeTransfer">;
    return this.manager.isMessageApproved(
      Ntt.messageDigest(chain, payload.nttManagerPayload)
    );
  }

  async getTokenDecimals(): Promise<number> {
    return await EvmPlatform.getDecimals(
      this.chain,
      this.provider,
      this.tokenAddress
    );
  }

  static async fromRpc<N extends Network>(
    provider: Provider,
    config: ChainsConfig<N, EvmPlatformType>
  ): Promise<EvmNtt<N, EvmChains>> {
    const [network, chain] = await EvmPlatform.chainFromRpc(provider);
    const conf = config[chain]!;
    if (conf.network !== network)
      throw new Error(`Network mismatch: ${conf.network} != ${network}`);

    const { ntt } = conf.contracts as { ntt: Ntt.Contracts };

    const version = await EvmNtt._getVersion(ntt.manager, provider);
    return new EvmNtt(network as N, chain, provider, conf.contracts, version);
  }

  encodeOptions(options: Ntt.TransferOptions): Ntt.TransceiverInstruction[] {
    const ixs: Ntt.TransceiverInstruction[] = [];

    ixs.push({
      index: 0,
      payload: this.xcvrs[0]!.encodeFlags({ skipRelay: !options.automatic }),
    });

    return ixs;
  }

  async getVersion(): Promise<string> {
    return EvmNtt._getVersion(this.managerAddress, this.provider);
  }

  static async _getVersion(address: string, provider: Provider) {
    const contract = new Contract(
      address,
      ["function NTT_MANAGER_VERSION() public view returns (string)"],
      provider
    );
    try {
      const abiVersion = await contract
        .getFunction("NTT_MANAGER_VERSION")
        .staticCall();
      if (!abiVersion) {
        throw new Error("NTT_MANAGER_VERSION not found");
      }
      return abiVersion;
    } catch (e) {
      console.error(
        `Failed to get NTT_MANAGER_VERSION from contract ${address}`
      );
      throw e;
    }
  }

  async getCustodyAddress() {
    return this.managerAddress;
  }

  async quoteDeliveryPrice(
    dstChain: Chain,
    options: Ntt.TransferOptions
  ): Promise<bigint> {
    const [, totalPrice] = await this.manager.quoteDeliveryPrice(
      toChainId(dstChain),
      Ntt.encodeTransceiverInstructions(this.encodeOptions(options))
    );
    return totalPrice;
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
    // in the future, these should(?) be keyed by attestation type
    yield* this.xcvrs[0]!.setPeer(peer);
  }

  async *transfer(
    sender: AccountAddress<C>,
    amount: bigint,
    destination: ChainAddress,
    options: Ntt.TransferOptions
  ): AsyncGenerator<EvmUnsignedTransaction<N, C>> {
    const senderAddress = new EvmAddress(sender).toString();

    // Note: these flags are indexed by transceiver index
    const totalPrice = await this.quoteDeliveryPrice(
      destination.chain,
      options
    );

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

    const receiver = universalAddress(destination);
    const txReq = await this.manager
      .getFunction("transfer(uint256,uint16,bytes32,bytes32,bool,bytes)")
      .populateTransaction(
        amount,
        toChainId(destination.chain),
        receiver,
        receiver,
        options.queue,
        Ntt.encodeTransceiverInstructions(this.encodeOptions(options)),
        { value: totalPrice }
      );

    yield this.createUnsignedTx(addFrom(txReq, senderAddress), "Ntt.transfer");
  }

  // TODO: should this be some map of idx to transceiver?
  async *redeem(attestations: Ntt.Attestation[]) {
    if (attestations.length !== this.xcvrs.length)
      throw new Error(
        "Not enough attestations for the registered Transceivers"
      );

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

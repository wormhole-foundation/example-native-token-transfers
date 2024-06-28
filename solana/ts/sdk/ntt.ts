import { Program, web3 } from "@coral-xyz/anchor";
import * as splToken from "@solana/spl-token";
import { createAssociatedTokenAccountInstruction } from "@solana/spl-token";
import {
  AddressLookupTableAccount,
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionMessage,
  VersionedTransaction,
} from "@solana/web3.js";
import {
  AccountAddress,
  Chain,
  ChainAddress,
  ChainsConfig,
  Contracts,
  NativeAddress,
  Network,
  TokenAddress,
  UnsignedTransaction,
  toUniversal,
} from "@wormhole-foundation/sdk-connect";
import {
  Ntt,
  NttTransceiver,
  WormholeNttTransceiver,
} from "@wormhole-foundation/sdk-definitions-ntt";
import {
  SolanaAddress,
  SolanaChains,
  SolanaPlatform,
  SolanaPlatformType,
  SolanaTransaction,
  SolanaUnsignedTransaction,
} from "@wormhole-foundation/sdk-solana";
import {
  SolanaWormholeCore,
  utils,
} from "@wormhole-foundation/sdk-solana-core";
import BN from "bn.js";
import { NTT, NttQuoter, WEI_PER_GWEI } from "../lib/index.js";

import { IdlVersion, NttBindings, getNttProgram } from "../lib/bindings.js";

export class SolanaNttWormholeTransceiver<N extends Network, C extends SolanaChains>
  implements NttTransceiver<N, C, WormholeNttTransceiver.VAA> {

  constructor(
    readonly manager: SolanaNtt<N, C>,
    readonly address: PublicKey
  ) {}

  async *receive(_attestation: WormholeNttTransceiver.VAA) {
    // TODO: this is implemented below (in the transceiver code). it could get
    // tricky in general with multiple transceivers, as they might return an
    // instruction, or multiple instructions, etc.
    // in any case, we should implement this here.
    throw new Error("Method not implemented.");
  }

  getAddress(): ChainAddress<C> {
    return { chain: this.manager.chain, address: toUniversal(this.manager.chain, this.address.toBase58()) };
  }

  async *setPeer(peer: ChainAddress<C>, payer: AccountAddress<C>) {
    yield* this.manager.setWormholeTransceiverPeer(peer, payer);
  }

  async getPeer<C extends Chain>(chain: C): Promise<ChainAddress<C> | null> {
    const peer =
      await this.manager.program.account.transceiverPeer.fetchNullable(
        this.manager.pdas.transceiverPeerAccount(chain)
      );

    if (!peer) return null;

    return {
      chain,
      address: toUniversal(chain, new Uint8Array(peer.address)),
    };
  }
}

export class SolanaNtt<N extends Network, C extends SolanaChains>
  implements Ntt<N, C> {
  core: SolanaWormholeCore<N, C>;
  pdas: NTT.Pdas;

  program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>;

  config?: NttBindings.Config<IdlVersion>;
  quoter?: NttQuoter;
  addressLookupTable?: AddressLookupTableAccount;

  // NOTE: these are stored from the constructor, but are not used directly
  // (only in verifyAddresses)
  private managerAddress: string;
  private tokenAddress: string;
  private whTransceiverAddress?: string;

  constructor(
    readonly network: N,
    readonly chain: C,
    readonly connection: Connection,
    readonly contracts: Contracts & { ntt?: Ntt.Contracts },
    readonly version: string = "2.0.0"
  ) {
    if (!contracts.ntt) throw new Error("Ntt contracts not found");

    this.program = getNttProgram(
      connection,
      contracts.ntt.manager,
      version as IdlVersion
    );

    this.managerAddress = contracts.ntt.manager;
    this.tokenAddress = contracts.ntt.token;
    this.whTransceiverAddress = contracts.ntt.transceiver.wormhole;

    if (this.contracts.ntt?.quoter)
      this.quoter = new NttQuoter(
        connection,
        this.contracts.ntt.quoter!,
        this.contracts.ntt.manager
      );

    this.core = new SolanaWormholeCore<N, C>(
      network,
      chain,
      connection,
      contracts
    );
    this.pdas = NTT.pdas(this.program.programId);
  }

  async getTransceiver(ix: number): Promise<NttTransceiver<N, C, any> | null> {
    if (ix !== 0) return null;
    if (this.whTransceiverAddress === undefined) return null;

    return new SolanaNttWormholeTransceiver(this, new PublicKey(this.whTransceiverAddress));
  }

  async getMode(): Promise<Ntt.Mode> {
    const config = await this.getConfig();
    return config.mode.locking != null ? "locking" : "burning";
  }

  async isPaused(): Promise<boolean> {
    const config = await this.getConfig();
    return config.paused;
  }

  async *pause(payer: AccountAddress<C>) {
    const sender = new SolanaAddress(payer).unwrap();
    const ix = await NTT.createSetPausedInstruction(this.program, {
      owner: sender,
      paused: true,
    });

    const tx = new Transaction();
    tx.feePayer = sender;
    tx.add(ix);
    yield this.createUnsignedTx({ transaction: tx }, "Ntt.Pause");
  }

  async *unpause(payer: AccountAddress<C>) {
    const sender = new SolanaAddress(payer).unwrap();
    const ix = await NTT.createSetPausedInstruction(this.program, {
      owner: sender,
      paused: false,
    });

    const tx = new Transaction();
    tx.feePayer = sender;
    tx.add(ix);
    yield this.createUnsignedTx({ transaction: tx }, "Ntt.Unpause");
  }

  async getThreshold(): Promise<number> {
    const config = await this.getConfig();
    return config.threshold
  }

  async getOwner(): Promise<AccountAddress<C>> {
    const config = await this.getConfig();
    return new SolanaAddress(config.owner) as AccountAddress<C>;
  }

  async *setOwner(newOwner: AccountAddress<C>, payer: AccountAddress<C>) {
    const sender = new SolanaAddress(payer).unwrap();
    const ix = await NTT.createTransferOwnershipInstruction(this.program, {
      newOwner: new SolanaAddress(newOwner).unwrap(),
    });

    const tx = new Transaction();
    tx.feePayer = sender;
    tx.add(ix);
    yield this.createUnsignedTx({ transaction: tx }, "Ntt.SetOwner");
  }

  async isRelayingAvailable(destination: Chain): Promise<boolean> {
    if (!this.quoter) return false;
    return await this.quoter.isRelayEnabled(destination);
  }

  async quoteDeliveryPrice(
    destination: Chain,
    options: Ntt.TransferOptions
  ): Promise<bigint> {
    if (!this.quoter) throw new Error("Quoter not available");
    if (!this.quoter.isRelayEnabled(destination))
      throw new Error("Relay not enabled");

    return await this.quoter.quoteDeliveryPrice(
      destination,
      options.gasDropoff
    );
  }

  static async fromRpc<N extends Network>(
    provider: Connection,
    config: ChainsConfig<N, SolanaPlatformType>
  ): Promise<SolanaNtt<N, SolanaChains>> {
    const [network, chain] = await SolanaPlatform.chainFromRpc(provider);
    const conf = config[chain]!;

    if (conf.network !== network)
      throw new Error(`Network mismatch: ${conf.network} != ${network}`);

    if (!("ntt" in conf.contracts)) throw new Error("Ntt contracts not found");
    const ntt = conf.contracts["ntt"];

    const version = await SolanaNtt.getVersion(
      provider,
      //@ts-ignore
      conf.contracts
    );

    return new SolanaNtt(
      network as N,
      chain,
      provider,
      { ...conf.contracts, ntt },
      version
    );
  }

  async getConfig(): Promise<NttBindings.Config<IdlVersion>> {
    this.config = this.config ?? (await NTT.getConfig(this.program, this.pdas));
    return this.config!;
  }

  async getTokenDecimals(): Promise<number> {
    const config = await this.getConfig();
    return await SolanaPlatform.getDecimals(
      this.chain,
      this.connection,
      config.mint
    );
  }

  async getPeer<C extends Chain>(chain: C): Promise<Ntt.Peer<C> | null> {
    const peer = await this.program.account.nttManagerPeer.fetchNullable(this.pdas.peerAccount(chain));

    if (!peer) return null;

    return {
      address: { chain: chain, address: toUniversal(chain, new Uint8Array(peer.address)) },
      tokenDecimals: peer.tokenDecimals,
      inboundLimit: await this.getInboundLimit(chain),
    };
  }

  async getCustodyAddress(): Promise<string> {
    return (await this.getConfig()).custody.toBase58();
  }

  static async getVersion(
    connection: Connection,
    contracts: Contracts & { ntt: Ntt.Contracts },
    sender?: AccountAddress<SolanaChains>
  ): Promise<IdlVersion> {
    // TODO: what? the try catch doesn't seem to work. it's not catching the error
    try {
      return NTT.getVersion(
        connection,
        new PublicKey(contracts.ntt.manager!),
        sender ? new SolanaAddress(sender).unwrap() : undefined
      );
    } catch (e) {
      const version = "2.0.0"
      console.error(`Failed to get NTT version. Defaulting to ${version}`);
      return version;
    }
  }

  async *initialize(
    sender: AccountAddress<C>,
    args: {
      mint: PublicKey;
      mode: Ntt.Mode;
      outboundLimit: bigint;
    }
  ) {
    const mintInfo = await this.connection.getAccountInfo(args.mint);
    if (mintInfo === null)
      throw new Error(
        "Couldn't determine token program. Mint account is null."
      );

    const payer = new SolanaAddress(sender).unwrap();

    const ix = await NTT.createInitializeInstruction(
      this.program,
      {
        ...args,
        payer,
        owner: payer,
        chain: this.chain,
        tokenProgram: mintInfo.owner,
      },
      this.pdas
    );

    const tx = new Transaction();
    tx.feePayer = payer;
    tx.add(ix);
    yield this.createUnsignedTx(
      { transaction: tx, signers: [] },
      "Ntt.Initialize"
    );

    yield* this.initializeOrUpdateLUT({ payer });
  }

  async *initializeOrUpdateLUT(args: { payer: PublicKey }) {
    const config = await this.getConfig();

    const ix = await NTT.initializeOrUpdateLUT(this.program, config, {
      payer: args.payer,
      wormholeId: new PublicKey(this.core.address),
    });
    // Already up to date
    if (!ix) return;

    const tx = new Transaction().add(ix);
    tx.feePayer = args.payer;

    yield this.createUnsignedTx({ transaction: tx }, "Ntt.InitializeLUT");
  }

  async *registerTransceiver(args: {
    payer: Keypair;
    owner: Keypair;
    transceiver: PublicKey;
  }) {
    const config = await this.getConfig();
    if (config.paused) throw new Error("Contract is paused");

    const ix = await this.program.methods
      .registerTransceiver()
      .accountsStrict({
        payer: args.payer.publicKey,
        owner: args.owner.publicKey,
        config: this.pdas.configAccount(),
        transceiver: args.transceiver,
        registeredTransceiver: this.pdas.registeredTransceiver(
          args.transceiver
        ),
        systemProgram: SystemProgram.programId,
      })
      .instruction();

    const wormholeMessage = Keypair.generate();
    const whAccs = utils.getWormholeDerivedAccounts(
      this.program.programId,
      this.core.address
    );
    const broadcastIx = await this.program.methods
      .broadcastWormholeId()
      .accountsStrict({
        payer: args.payer.publicKey,
        config: this.pdas.configAccount(),
        mint: config.mint,
        wormholeMessage: wormholeMessage.publicKey,
        emitter: this.pdas.emitterAccount(),
        wormhole: {
          bridge: whAccs.wormholeBridge,
          feeCollector: whAccs.wormholeFeeCollector,
          sequence: whAccs.wormholeSequence,
          program: this.core.address,
          systemProgram: SystemProgram.programId,
          clock: web3.SYSVAR_CLOCK_PUBKEY,
          rent: web3.SYSVAR_RENT_PUBKEY,
        },
      })
      .instruction();

    const tx = new Transaction();
    tx.feePayer = args.payer.publicKey;
    tx.add(ix, broadcastIx);
    yield this.createUnsignedTx(
      { transaction: tx, signers: [wormholeMessage] },
      "Ntt.RegisterTransceiver"
    );
  }

  async *setWormholeTransceiverPeer(
    peer: ChainAddress,
    payer: AccountAddress<C>
  ) {
    const sender = new SolanaAddress(payer).unwrap();
    yield this.createUnsignedTx(
      await NTT.setWormholeTransceiverPeer(this.program, {
        wormholeId: new PublicKey(this.core.address),
        payer: sender,
        owner: sender,
        chain: peer.chain,
        address: peer.address.toUniversalAddress().toUint8Array(),
      }),
      "Ntt.SetWormholeTransceiverPeer"
    );
  }

  async *setPeer(
    peer: ChainAddress,
    tokenDecimals: number,
    inboundLimit: bigint,
    payer: AccountAddress<C>
  ) {
    const sender = new SolanaAddress(payer).unwrap();

    const ix = await NTT.createSetPeerInstruction(this.program, {
      payer: sender,
      owner: sender,
      chain: peer.chain,
      address: peer.address.toUniversalAddress().toUint8Array(),
      limit: new BN(inboundLimit.toString()),
      tokenDecimals,
    });

    const tx = new Transaction();
    tx.feePayer = sender;
    tx.add(ix);
    yield this.createUnsignedTx({ transaction: tx }, "Ntt.SetPeer");
  }

  async *transfer(
    sender: AccountAddress<C>,
    amount: bigint,
    destination: ChainAddress,
    options: Ntt.TransferOptions,
    outboxItem?: Keypair
  ): AsyncGenerator<UnsignedTransaction<N, C>, any, unknown> {
    const config = await this.getConfig();
    if (config.paused) throw new Error("Contract is paused");

    outboxItem = outboxItem ?? Keypair.generate();

    const payerAddress = new SolanaAddress(sender).unwrap();
    const fromAuthority = payerAddress;
    const from = await this.getTokenAccount(fromAuthority);

    const transferArgs = NTT.transferArgs(amount, destination, options.queue);

    const txArgs = {
      transferArgs,
      payer: payerAddress,
      from,
      fromAuthority,
      outboxItem: outboxItem.publicKey,
    };

    const approveIx = splToken.createApproveInstruction(
      from,
      this.pdas.sessionAuthority(fromAuthority, transferArgs),
      fromAuthority,
      amount,
      [],
      config.tokenProgram
    );

    const transferIx =
      config.mode.locking != null
        ? NTT.createTransferLockInstruction(
          this.program,
          config,
          txArgs,
          this.pdas
        )
        : NTT.createTransferBurnInstruction(
          this.program,
          config,
          txArgs,
          this.pdas
        );

    const releaseIx = NTT.createReleaseOutboundInstruction(
      this.program,
      {
        payer: payerAddress,
        outboxItem: outboxItem.publicKey,
        revertOnDelay: !options.queue,
        wormholeId: new PublicKey(this.core.address),
      },
      this.pdas
    );

    const tx = new Transaction();
    tx.feePayer = payerAddress;
    tx.add(approveIx, ...(await Promise.all([transferIx, releaseIx])));

    if (options.automatic) {
      if (!this.quoter)
        throw new Error(
          "No quoter available, cannot initiate an automatic transfer."
        );

      const fee = await this.quoteDeliveryPrice(destination.chain, options);

      const relayIx = await this.quoter.createRequestRelayInstruction(
        payerAddress,
        outboxItem.publicKey,
        destination.chain,
        Number(fee),
        // Note: quoter expects gas dropoff to be in terms of gwei
        Number(options.gasDropoff ?? 0n) / WEI_PER_GWEI
      );
      tx.add(relayIx);
    }

    const luts: AddressLookupTableAccount[] = [];
    try {
      luts.push(await this.getAddressLookupTable());
    } catch {}

    const messageV0 = new TransactionMessage({
      payerKey: payerAddress,
      instructions: tx.instructions,
      recentBlockhash: (await this.connection.getRecentBlockhash()).blockhash,
    }).compileToV0Message(luts);

    const vtx = new VersionedTransaction(messageV0);

    yield this.createUnsignedTx(
      { transaction: vtx, signers: [outboxItem] },
      "Ntt.Transfer"
    );
  }

  private async getTokenAccount(sender: PublicKey): Promise<PublicKey> {
    const config = await this.getConfig();
    const tokenAccount = await splToken.getAssociatedTokenAddress(
      config.mint,
      sender,
      true,
      config.tokenProgram
    );
    return tokenAccount;
  }

  private async *createAta(sender: AccountAddress<C>) {
    const config = await this.getConfig();
    const senderAddress = new SolanaAddress(sender).unwrap();

    const ata = await this.getTokenAccount(senderAddress);

    // If the ata doesn't exist yet, create it
    const acctInfo = await this.connection.getAccountInfo(ata);
    if (acctInfo === null) {
      const transaction = new Transaction().add(
        createAssociatedTokenAccountInstruction(
          senderAddress,
          ata,
          senderAddress,
          config.mint,
          config.tokenProgram
        )
      );
      transaction.feePayer = senderAddress;
      yield this.createUnsignedTx({ transaction }, "Redeem.CreateATA");
    }
  }

  async *redeem(attestations: Ntt.Attestation[], payer: AccountAddress<C>) {
    const config = await this.getConfig();
    if (config.paused) throw new Error("Contract is paused");

    // TODO: not this, we should iterate over the set of enabled xcvrs?
    // if (attestations.length !== this.xcvrs.length) throw "No";
    const wormholeNTT = attestations[0]! as WormholeNttTransceiver.VAA;

    // Create the vaa if necessary
    yield* this.createAta(payer);

    // Post the VAA that we intend to redeem
    yield* this.core.postVaa(payer, wormholeNTT);

    const senderAddress = new SolanaAddress(payer).unwrap();

    const receiveMessageIx = NTT.createReceiveWormholeMessageInstruction(
      this.program,
      {
        wormholeId: new PublicKey(this.core.address),
        payer: senderAddress,
        vaa: wormholeNTT,
      },
      this.pdas
    );

    const nttMessage = wormholeNTT.payload.nttManagerPayload;
    const emitterChain = wormholeNTT.emitterChain;
    const releaseArgs = {
      payer: senderAddress,
      config,
      nttMessage,
      recipient: new PublicKey(
        nttMessage.payload.recipientAddress.toUint8Array()
      ),
      chain: emitterChain,
      revertOnDelay: false,
    };

    // TODO: loop through transceivers etc.
    const redeemIx = NTT.createRedeemInstruction(this.program, config, {
      payer: senderAddress,
      vaa: wormholeNTT,
    });

    const releaseIx =
      config.mode.locking != null
        ? NTT.createReleaseInboundUnlockInstruction(
          this.program,
          config,
          releaseArgs
        )
        : NTT.createReleaseInboundMintInstruction(
          this.program,
          config,
          releaseArgs
        );

    const tx = new Transaction();
    tx.feePayer = senderAddress;
    tx.add(...(await Promise.all([receiveMessageIx, redeemIx, releaseIx])));

    const luts: AddressLookupTableAccount[] = [];
    try {
      luts.push(await this.getAddressLookupTable());
    } catch {}

    const messageV0 = new TransactionMessage({
      payerKey: senderAddress,
      instructions: tx.instructions,
      recentBlockhash: (await this.connection.getRecentBlockhash()).blockhash,
    }).compileToV0Message(luts);

    const vtx = new VersionedTransaction(messageV0);

    yield this.createUnsignedTx({ transaction: vtx }, "Ntt.Redeem");
  }

  async getCurrentOutboundCapacity(): Promise<bigint> {
    const rl = await this.program.account.outboxRateLimit.fetch(
      this.pdas.outboxRateLimitAccount()
    );
    return BigInt(rl.rateLimit.capacityAtLastTx.toString());
  }

  async getOutboundLimit(): Promise<bigint> {
    const rl = await this.program.account.outboxRateLimit.fetch(
      this.pdas.outboxRateLimitAccount()
    );
    return BigInt(rl.rateLimit.limit.toString());
  }

  async *setOutboundLimit(limit: bigint, payer: AccountAddress<C>) {
    const sender = new SolanaAddress(payer).unwrap();
    const ix = await NTT.createSetOutboundLimitInstruction(this.program, {
      owner: sender,
      limit: new BN(limit.toString()),
    });

    const tx = new Transaction();
    tx.feePayer = sender;
    tx.add(ix);
    yield this.createUnsignedTx({ transaction: tx }, "Ntt.SetOutboundLimit");
  }

  async getCurrentInboundCapacity(fromChain: Chain): Promise<bigint> {
    const rl = await this.program.account.inboxRateLimit.fetch(
      this.pdas.inboxRateLimitAccount(fromChain)
    );
    return BigInt(rl.rateLimit.capacityAtLastTx.toString());
  }

  async getInboundLimit(fromChain: Chain): Promise<bigint> {
    const rl = await this.program.account.inboxRateLimit.fetch(
      this.pdas.inboxRateLimitAccount(fromChain)
    );
    return BigInt(rl.rateLimit.limit.toString());
  }

  async *setInboundLimit(
    fromChain: Chain,
    limit: bigint,
    payer: AccountAddress<C>
  ) {
    const sender = new SolanaAddress(payer).unwrap();
    const ix = await NTT.setInboundLimit(this.program, {
      owner: sender,
      chain: fromChain,
      limit: new BN(limit.toString()),
    });

    const tx = new Transaction();
    tx.feePayer = sender;
    tx.add(ix);
    yield this.createUnsignedTx({ transaction: tx }, "Ntt.SetInboundLimit");
  }

  async getIsExecuted(attestation: Ntt.Attestation): Promise<boolean> {
    if (!this.getIsApproved(attestation)) return false;

    const { emitterChain } = attestation as WormholeNttTransceiver.VAA;
    const inboundQueued = await this.getInboundQueuedTransfer(
      emitterChain,
      attestation
    );

    return inboundQueued === null;
  }

  async getIsApproved(attestation: Ntt.Attestation): Promise<boolean> {
    const digest = (attestation as WormholeNttTransceiver.VAA).hash;
    const vaaAddress = utils.derivePostedVaaKey(
      this.core.address,
      Buffer.from(digest)
    );

    try {
      const info = this.connection.getAccountInfo(vaaAddress);
      return info !== null;
    } catch (_) {}

    return false;
  }

  async *completeInboundQueuedTransfer(
    fromChain: Chain,
    transceiverMessage: Ntt.Message,
    token: TokenAddress<C>,
    payer: AccountAddress<C>
  ) {
    const config = await this.getConfig();
    if (config.paused) throw new Error("Contract is paused");

    const senderAddress = new SolanaAddress(payer).unwrap();
    const tx = new Transaction();
    tx.feePayer = senderAddress;
    const releaseArgs = {
      payer: senderAddress,
      config,
      nttMessage: transceiverMessage,
      recipient: new PublicKey(
        transceiverMessage.payload.recipientAddress.toUint8Array()
      ),
      chain: fromChain,
      revertOnDelay: false,
    };

    tx.add(
      await (config.mode.locking != null
        ? NTT.createReleaseInboundUnlockInstruction(
          this.program,
          config,
          releaseArgs
        )
        : NTT.createReleaseInboundMintInstruction(
          this.program,
          config,
          releaseArgs
        ))
    );

    yield this.createUnsignedTx(
      { transaction: tx },
      "Ntt.CompleteInboundTransfer"
    );
  }

  async getInboundQueuedTransfer(
    chain: Chain,
    nttMessage: Ntt.Message
  ): Promise<Ntt.InboundQueuedTransfer<C> | null> {
    const inboxItem = await this.program.account.inboxItem.fetch(
      this.pdas.inboxItemAccount(chain, nttMessage)
    );
    if (!inboxItem) return null;

    const { recipientAddress, amount, releaseStatus } = inboxItem!;
    const rateLimitExpiry = releaseStatus.releaseAfter
      ? releaseStatus.releaseAfter[0].toNumber()
      : 0;

    const xfer: Ntt.InboundQueuedTransfer<C> = {
      recipient: new SolanaAddress(recipientAddress) as NativeAddress<C>,
      amount: BigInt(amount.toString()),
      rateLimitExpiryTimestamp: rateLimitExpiry,
    };

    return xfer;
  }

  async verifyAddresses(): Promise<Partial<Ntt.Contracts> | null> {
    const local: Partial<Ntt.Contracts> = {
      manager: this.managerAddress,
      token: this.tokenAddress,
      transceiver: {
        wormhole: this.whTransceiverAddress,
      },
    };

    const remote: Partial<Ntt.Contracts> = {
      manager: this.program.programId.toBase58(),
      token: (await this.getConfig()).mint.toBase58(),
      transceiver: { wormhole: this.pdas.emitterAccount().toBase58() },
    };

    const deleteMatching = (a: any, b: any) => {
      for (const k in a) {
        if (typeof a[k] === "object") {
          deleteMatching(a[k], b[k]);
          if (Object.keys(a[k]).length === 0) delete a[k];
        } else if (a[k] === b[k]) {
          delete a[k];
        }
      }
    }

    deleteMatching(remote, local);

    return Object.keys(remote).length > 0 ? remote : null;
  }

  async getAddressLookupTable(
    useCache = true
  ): Promise<AddressLookupTableAccount> {
    if (!useCache || !this.addressLookupTable) {
      const alut = await NTT.getAddressLookupTable(this.program, this.pdas);
      if (alut) this.addressLookupTable = alut;
    }

    if (!this.addressLookupTable)
      throw new Error(
        "Address lookup table not found. Did you forget to call initializeLUT?"
      );

    return this.addressLookupTable;
  }

  createUnsignedTx(
    txReq: SolanaTransaction,
    description: string,
    parallelizable: boolean = false
  ): SolanaUnsignedTransaction<N, C> {
    return new SolanaUnsignedTransaction(
      txReq,
      this.network,
      this.chain,
      description,
      parallelizable
    );
  }
}

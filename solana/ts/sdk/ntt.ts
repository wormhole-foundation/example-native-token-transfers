import { Program, web3 } from "@coral-xyz/anchor";
import * as splToken from "@solana/spl-token";
import { createAssociatedTokenAccountInstruction } from "@solana/spl-token";
import {
  AddressLookupTableAccount,
  AddressLookupTableProgram,
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
  toChainId,
} from "@wormhole-foundation/sdk-connect";
import {
  Ntt,
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

export class SolanaNtt<N extends Network, C extends SolanaChains>
  implements Ntt<N, C>
{
  core: SolanaWormholeCore<N, C>;
  pdas: NTT.Pdas;

  program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>;

  config?: NttBindings.Config<IdlVersion>;
  quoter?: NttQuoter;
  addressLookupTable?: AddressLookupTableAccount;

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

  async getCustodyAddress(): Promise<string> {
    return (await this.getConfig()).custody.toBase58();
  }

  static async getVersion(
    connection: Connection,
    contracts: Contracts & { ntt: Ntt.Contracts },
    sender?: AccountAddress<SolanaChains>
  ): Promise<IdlVersion> {
    return NTT.getVersion(
      connection,
      new PublicKey(contracts.ntt.manager!),
      sender ? new SolanaAddress(sender).unwrap() : undefined
    );
  }

  async *initialize(args: {
    payer: PublicKey;
    owner: PublicKey;
    chain: Chain;
    mint: PublicKey;
    outboundLimit: bigint;
    mode: "burning" | "locking";
  }) {
    const mintInfo = await this.connection.getAccountInfo(args.mint);
    if (mintInfo === null)
      throw new Error(
        "Couldn't determine token program. Mint account is null."
      );

    const ix = await NTT.createInitializeInstruction(
      this.program,
      { ...args, tokenProgram: mintInfo.owner },
      this.pdas
    );

    const tx = new Transaction();
    tx.feePayer = args.payer;
    tx.add(ix);
    yield this.createUnsignedTx(
      { transaction: tx, signers: [] },
      "Ntt.Initialize"
    );

    yield* this.initializeOrUpdateLUT({ payer: args.payer });
  }

  // This function should be called after each upgrade. If there's nothing to
  // do, it won't actually submit a transaction, so it's cheap to call.
  async *initializeOrUpdateLUT(args: { payer: PublicKey }) {
    if (this.version === "1.0.0") return;
    const program = this.program as Program<
      NttBindings.NativeTokenTransfer<"2.0.0">
    >;

    // TODO: find a more robust way of fetching a recent slot
    const slot = (await this.connection.getSlot()) - 1;

    const [_, lutAddress] = web3.AddressLookupTableProgram.createLookupTable({
      authority: this.pdas.lutAuthority(),
      payer: args.payer,
      recentSlot: slot,
    });

    const whAccs = utils.getWormholeDerivedAccounts(
      program.programId,
      this.core.address
    );
    const config = await this.getConfig();

    const entries = {
      config: this.pdas.configAccount(),
      custody: config.custody,
      tokenProgram: config.tokenProgram,
      mint: config.mint,
      tokenAuthority: this.pdas.tokenAuthority(),
      outboxRateLimit: this.pdas.outboxRateLimitAccount(),
      wormhole: {
        bridge: whAccs.wormholeBridge,
        feeCollector: whAccs.wormholeFeeCollector,
        sequence: whAccs.wormholeSequence,
        program: this.core.address,
        systemProgram: SystemProgram.programId,
        clock: web3.SYSVAR_CLOCK_PUBKEY,
        rent: web3.SYSVAR_RENT_PUBKEY,
      },
    };

    // collect all pubkeys in entries recursively
    const collectPubkeys = (obj: any): Array<PublicKey> => {
      const pubkeys = new Array<PublicKey>();
      for (const key in obj) {
        const value = obj[key];
        if (value instanceof PublicKey) {
          pubkeys.push(value);
        } else if (typeof value === "object") {
          pubkeys.push(...collectPubkeys(value));
        }
      }
      return pubkeys;
    };
    const pubkeys = collectPubkeys(entries).map((pk) => pk.toBase58());

    var existingLut: web3.AddressLookupTableAccount | null = null;
    try {
      existingLut = await this.getAddressLookupTable(false);
    } catch {
      // swallow errors here, it just means that lut doesn't exist
    }

    if (existingLut !== null) {
      const existingPubkeys =
        existingLut.state.addresses?.map((a) => a.toBase58()) ?? [];

      // if pubkeys contains keys that are not in the existing LUT, we need to
      // add them to the LUT
      const missingPubkeys = pubkeys.filter(
        (pk) => !existingPubkeys.includes(pk)
      );

      if (missingPubkeys.length === 0) {
        return existingLut;
      }
    }

    const ix = await program.methods
      .initializeLut(new BN(slot))
      .accountsStrict({
        payer: args.payer,
        authority: this.pdas.lutAuthority(),
        lutAddress,
        lut: this.pdas.lutAccount(),
        lutProgram: AddressLookupTableProgram.programId,
        systemProgram: SystemProgram.programId,
        entries,
      })
      .instruction();

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
    const wormholeMessage = Keypair.generate();
    const whAccs = utils.getWormholeDerivedAccounts(
      this.program.programId,
      this.core.address
    );

    const [setPeerIx, broadcastIx] = await Promise.all([
      this.program.methods
        .setWormholePeer({
          chainId: { id: toChainId(peer.chain) },
          address: Array.from(peer.address.toUniversalAddress().toUint8Array()),
        })
        .accountsStrict({
          payer: sender,
          owner: sender,
          config: this.pdas.configAccount(),
          peer: this.pdas.transceiverPeerAccount(peer.chain),
          systemProgram: SystemProgram.programId,
        })
        .instruction(),
      this.program.methods
        .broadcastWormholePeer({ chainId: toChainId(peer.chain) })
        .accountsStrict({
          payer: sender,
          config: this.pdas.configAccount(),
          peer: this.pdas.transceiverPeerAccount(peer.chain),
          wormholeMessage: wormholeMessage.publicKey,
          emitter: this.pdas.emitterAccount(),
          wormhole: {
            bridge: whAccs.wormholeBridge,
            feeCollector: whAccs.wormholeFeeCollector,
            sequence: whAccs.wormholeSequence,
            program: this.core.address,
            clock: web3.SYSVAR_CLOCK_PUBKEY,
            rent: web3.SYSVAR_RENT_PUBKEY,
            systemProgram: SystemProgram.programId,
          },
        })
        .instruction(),
    ]);

    const tx = new Transaction();
    tx.feePayer = sender;
    tx.add(setPeerIx, broadcastIx);

    yield this.createUnsignedTx(
      {
        transaction: tx,
        signers: [wormholeMessage],
      },
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

    const ix = await this.program.methods
      .setPeer({
        chainId: { id: toChainId(peer.chain) },
        address: Array.from(peer.address.toUniversalAddress().toUint8Array()),
        limit: new BN(inboundLimit.toString()),
        tokenDecimals: tokenDecimals,
      })
      .accountsStrict({
        payer: sender,
        owner: sender,
        config: this.pdas.configAccount(),
        peer: this.pdas.peerAccount(peer.chain),
        inboxRateLimit: this.pdas.inboxRateLimitAccount(peer.chain),
        systemProgram: SystemProgram.programId,
      })
      .instruction();

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

  async getCurrentInboundCapacity(fromChain: Chain): Promise<bigint> {
    const rl = await this.program.account.inboxRateLimit.fetch(
      this.pdas.inboxRateLimitAccount(fromChain)
    );
    return BigInt(rl.rateLimit.capacityAtLastTx.toString());
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

  async getAddressLookupTable(
    useCache = true
  ): Promise<AddressLookupTableAccount> {
    if (this.version === "1.0.0")
      throw new Error("Lookup tables not supported for this version");

    if (!useCache || !this.addressLookupTable) {
      // @ts-ignore
      const lut = await this.program.account.lut.fetchNullable(
        this.pdas.lutAccount()
      );
      if (!lut)
        throw new Error(
          "Address lookup table not found. Did you forget to call initializeLUT?"
        );

      const response = await this.connection.getAddressLookupTable(lut.address);
      if (response.value === null) throw new Error("Could not fetch LUT");

      this.addressLookupTable = response.value;
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

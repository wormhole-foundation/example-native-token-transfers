import { Program } from "@coral-xyz/anchor";
import { associatedAddress } from "@coral-xyz/anchor/dist/cjs/utils/token.js";
import * as splToken from "@solana/spl-token";
import {
  createAssociatedTokenAccountInstruction,
  getAssociatedTokenAddressSync,
} from "@solana/spl-token";
import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
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
  deserializeLayout,
  encoding,
  toChain,
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
import {
  BPF_LOADER_UPGRADEABLE_PROGRAM_ID,
  TransferArgs,
  nttAddresses,
  programDataAddress,
  programVersionLayout,
} from "./utils.js";

import {
  IdlVersion,
  IdlVersions,
  NttBindings,
  getNttProgram,
} from "./bindings.js";
import { NttQuoter } from "./quoter.js";

export class SolanaNtt<N extends Network, C extends SolanaChains>
  implements Ntt<N, C>
{
  core: SolanaWormholeCore<N, C>;
  pdas: ReturnType<typeof nttAddresses>;

  program: Program<NttBindings.NativeTokenTransfer>;
  config?: NttBindings.Config;
  quoter?: NttQuoter<N, C>;

  constructor(
    readonly network: N,
    readonly chain: C,
    readonly connection: Connection,
    readonly contracts: Contracts & { ntt?: Ntt.Contracts },
    readonly idlVersion: IdlVersion = "default"
  ) {
    if (!contracts.ntt) throw new Error("Ntt contracts not found");

    this.program = getNttProgram(connection, contracts.ntt.manager, idlVersion);
    if (this.contracts.ntt?.quoter)
      this.quoter = new NttQuoter(network, chain, connection, this.contracts);

    this.core = new SolanaWormholeCore<N, C>(
      network,
      chain,
      connection,
      contracts
    );
    this.pdas = nttAddresses(this.program.programId);
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

    const version = await SolanaNtt._getVersion(ntt.manager, provider);

    return new SolanaNtt(
      network as N,
      chain,
      provider,
      { ...conf.contracts, ntt },
      version
    );
  }

  async getConfig(): Promise<NttBindings.Config> {
    this.config =
      this.config ??
      (await this.program.account.config.fetch(this.pdas.configAccount()));
    return this.config;
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

  async getVersion(sender: AccountAddress<C>): Promise<string> {
    return await SolanaNtt._getVersion(
      this.program.programId.toBase58(),
      this.connection,
      sender
    );
  }

  static async _getVersion(
    programAddress: string,
    connection: Connection,
    sender?: AccountAddress<SolanaChains>
  ): Promise<IdlVersion> {
    // the anchor library has a built-in method to read view functions. However,
    // it requires a signer, which would trigger a wallet prompt on the frontend.
    // Instead, we manually construct a versioned transaction and call the
    // simulate function with sigVerify: false below.
    //
    // This way, the simulation won't require a signer, but it still requires
    // the pubkey of an account that has some lamports in it (since the
    // simulation checks if the account has enough money to pay for the transaction).
    //
    // It's a little unfortunate but it's the best we can do.

    if (!sender)
      sender = new SolanaAddress(
        // The default pubkey is funded on mainnet and devnet
        // we need a funded account to simulate the transaction below
        "Hk3SdYTJFpawrvRz4qRztuEt2SqoCG7BGj2yJfDJSFbJ"
      );

    const senderAddress = new SolanaAddress(sender).unwrap();

    const program = getNttProgram(connection, programAddress);

    const ix = await program.methods.version().accountsStrict({}).instruction();
    const latestBlockHash =
      await program.provider.connection.getLatestBlockhash();

    const msg = new TransactionMessage({
      payerKey: senderAddress,
      recentBlockhash: latestBlockHash.blockhash,
      instructions: [ix],
    }).compileToV0Message();

    const tx = new VersionedTransaction(msg);

    const txSimulation = await program.provider.connection.simulateTransaction(
      tx,
      { sigVerify: false }
    );

    const data = encoding.b64.decode(txSimulation.value.returnData?.data[0]!);
    const parsed = deserializeLayout(programVersionLayout, data);
    const version = encoding.bytes.decode(parsed.version);
    if (version in IdlVersions) return version as IdlVersion;
    else throw new Error("Unknown IDL version: " + version);
  }

  async *initialize(args: {
    payer: Keypair;
    owner: Keypair;
    chain: Chain;
    mint: PublicKey;
    outboundLimit: bigint;
    mode: "burning" | "locking";
  }) {
    const mode: any =
      args.mode === "burning" ? { burning: {} } : { locking: {} };
    const chainId = toChainId(args.chain);
    const mintInfo = await this.program.provider.connection.getAccountInfo(
      args.mint
    );
    if (mintInfo === null) {
      throw new Error(
        "Couldn't determine token program. Mint account is null."
      );
    }

    const custodyAddress = associatedAddress({
      mint: args.mint,
      owner: this.pdas.tokenAuthority(),
    });

    const tokenProgram = mintInfo.owner;
    const limit = new BN(args.outboundLimit.toString());
    const ix = await this.program.methods
      .initialize({ chainId, limit: limit, mode })
      .accounts({
        payer: args.payer.publicKey,
        deployer: args.owner.publicKey,
        programData: programDataAddress(this.program.programId),
        config: this.pdas.configAccount(),
        mint: args.mint,
        rateLimit: this.pdas.outboxRateLimitAccount(),
        tokenProgram,
        tokenAuthority: this.pdas.tokenAuthority(),
        custody: custodyAddress,
        bpfLoaderUpgradeableProgram: BPF_LOADER_UPGRADEABLE_PROGRAM_ID,
      })
      .instruction();

    const tx = new Transaction();
    tx.feePayer = args.payer.publicKey;
    tx.add(ix);
    yield this.createUnsignedTx(
      { transaction: tx, signers: [] },
      "Ntt.Initialize"
    );
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
      .accounts({
        payer: args.payer.publicKey,
        owner: args.owner.publicKey,
        config: this.pdas.configAccount(),
        transceiver: args.transceiver,
        registeredTransceiver: this.pdas.registeredTransceiver(
          args.transceiver
        ),
      })
      .instruction();

    const wormholeMessage = Keypair.generate();
    const whAccs = utils.getWormholeDerivedAccounts(
      this.program.programId,
      this.core.address
    );
    const broadcastIx = await this.program.methods
      .broadcastWormholeId()
      .accounts({
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
        .accounts({
          payer: sender,
          owner: sender,
          config: this.pdas.configAccount(),
          peer: this.pdas.transceiverPeerAccount(peer.chain),
        })
        .instruction(),
      this.program.methods
        .broadcastWormholePeer({ chainId: toChainId(peer.chain) })
        .accounts({
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
      .accounts({
        payer: sender,
        owner: sender,
        config: this.pdas.configAccount(),
        peer: this.pdas.peerAccount(peer.chain),
        inboxRateLimit: this.pdas.inboxRateLimitAccount(peer.chain),
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

    const senderAddress = new SolanaAddress(sender).unwrap();
    const fromAuthority = senderAddress;
    const from = getAssociatedTokenAddressSync(config.mint, fromAuthority);

    const transferArgs: TransferArgs = {
      amount: amount,
      recipient: destination,
      shouldQueue: options.queue,
    };

    const txArgs = {
      transferArgs,
      payer: senderAddress,
      from,
      fromAuthority,
      outboxItem: outboxItem.publicKey,
      config,
    };

    const [approveIx, transferIx, releaseIx] = await Promise.all([
      splToken.createApproveInstruction(
        from,
        this.pdas.sessionAuthority(fromAuthority, transferArgs),
        fromAuthority,
        amount
      ),
      config.mode.locking != null
        ? this.createTransferLockInstruction(txArgs)
        : this.createTransferBurnInstruction(txArgs),
      this.createReleaseOutboundInstruction({
        payer: senderAddress,
        outboxItem: outboxItem.publicKey,
        revertOnDelay: !options.queue,
      }),
    ]);

    const tx = new Transaction();
    tx.feePayer = senderAddress;
    tx.add(approveIx, transferIx, releaseIx);

    if (options.automatic) {
      if (!this.quoter)
        throw new Error(
          "No quoter available, cannot initiate an automatic transfer."
        );

      const fee = await this.quoteDeliveryPrice(destination.chain, options);
      const relayIx = await this.quoter.createRequestRelayInstruction(
        senderAddress,
        outboxItem.publicKey,
        this.program.programId,
        destination.chain,
        new BN(fee.toString()),
        new BN((options.gasDropoff ?? 0n).toString())
      );
      tx.add(relayIx);
    }

    yield this.createUnsignedTx(
      { transaction: tx, signers: [outboxItem] },
      "Ntt.Transfer"
    );
  }

  private async *createAta(sender: AccountAddress<C>, mint: PublicKey) {
    const senderAddress = new SolanaAddress(sender).unwrap();
    const ata = getAssociatedTokenAddressSync(mint, senderAddress);

    // If the ata doesn't exist yet, create it
    const acctInfo = await this.connection.getAccountInfo(ata);
    if (acctInfo === null) {
      const transaction = new Transaction().add(
        createAssociatedTokenAccountInstruction(
          senderAddress,
          ata,
          senderAddress,
          mint
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
    yield* this.createAta(payer, config.mint);

    // Post the VAA that we intend to redeem
    yield* this.core.postVaa(payer, wormholeNTT);

    const senderAddress = new SolanaAddress(payer).unwrap();
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

    const [receiveMessageIx, redeemIx, releaseIx] = await Promise.all([
      this.createReceiveWormholeMessageInstruction(senderAddress, wormholeNTT),
      this.createRedeemInstruction(senderAddress, wormholeNTT),
      config.mode.locking != null
        ? this.createReleaseInboundUnlockInstruction(releaseArgs)
        : this.createReleaseInboundMintInstruction(releaseArgs),
    ]);

    const tx = new Transaction();
    tx.feePayer = senderAddress;
    tx.add(receiveMessageIx, redeemIx, releaseIx);
    yield this.createUnsignedTx({ transaction: tx }, "Ntt.Redeem");
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
        ? this.createReleaseInboundUnlockInstruction(releaseArgs)
        : this.createReleaseInboundMintInstruction(releaseArgs))
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

  async createTransferLockInstruction(args: {
    transferArgs: TransferArgs;
    payer: PublicKey;
    from: PublicKey;
    fromAuthority: PublicKey;
    outboxItem: PublicKey;
    config?: NttBindings.Config;
  }): Promise<TransactionInstruction> {
    const config = await this.getConfig();
    if (config.paused) throw new Error("Contract is paused");

    const sessionAuthority = this.pdas.sessionAuthority(
      args.fromAuthority,
      args.transferArgs
    );

    const recipientChain = args.transferArgs.recipient.chain;
    return await this.program.methods
      .transferLock({
        recipientChain: { id: toChainId(recipientChain) },
        amount: new BN(args.transferArgs.amount.toString()),
        recipientAddress: Array.from(
          args.transferArgs.recipient.address
            .toUniversalAddress()
            .toUint8Array()
        ),
        shouldQueue: args.transferArgs.shouldQueue,
      })
      .accounts({
        common: {
          payer: args.payer,
          config: { config: this.pdas.configAccount() },
          mint: config.mint,
          from: args.from,
          tokenProgram: config.tokenProgram,
          outboxItem: args.outboxItem,
          outboxRateLimit: this.pdas.outboxRateLimitAccount(),
        },
        peer: this.pdas.peerAccount(recipientChain),
        inboxRateLimit: this.pdas.inboxRateLimitAccount(recipientChain),
        custody: config.custody,
        sessionAuthority: sessionAuthority,
      })
      .instruction();
  }

  async createTransferBurnInstruction(args: {
    transferArgs: TransferArgs;
    payer: PublicKey;
    from: PublicKey;
    fromAuthority: PublicKey;
    outboxItem: PublicKey;
    config?: NttBindings.Config;
  }): Promise<TransactionInstruction> {
    const config = await this.getConfig();
    if (config.paused) throw new Error("Contract is paused");

    const recipientChain = toChain(args.transferArgs.recipient.chain);
    return await this.program.methods
      .transferBurn({
        recipientChain: { id: toChainId(recipientChain) },
        amount: new BN(args.transferArgs.amount.toString()),
        recipientAddress: Array.from(
          args.transferArgs.recipient.address
            .toUniversalAddress()
            .toUint8Array()
        ),
        shouldQueue: args.transferArgs.shouldQueue,
      })
      .accounts({
        common: {
          payer: args.payer,
          config: { config: this.pdas.configAccount() },
          mint: config.mint,
          from: args.from,
          outboxItem: args.outboxItem,
          outboxRateLimit: this.pdas.outboxRateLimitAccount(),
        },
        peer: this.pdas.peerAccount(recipientChain),
        inboxRateLimit: this.pdas.inboxRateLimitAccount(recipientChain),
        sessionAuthority: this.pdas.sessionAuthority(
          args.fromAuthority,
          args.transferArgs
        ),
      })
      .instruction();
  }

  async createReleaseOutboundInstruction(args: {
    payer: PublicKey;
    outboxItem: PublicKey;
    revertOnDelay: boolean;
  }): Promise<TransactionInstruction> {
    const whAccs = utils.getWormholeDerivedAccounts(
      this.program.programId,
      this.core.address
    );

    return await this.program.methods
      .releaseWormholeOutbound({
        revertOnDelay: args.revertOnDelay,
      })
      .accounts({
        payer: args.payer,
        config: { config: this.pdas.configAccount() },
        outboxItem: args.outboxItem,
        wormholeMessage: this.pdas.wormholeMessageAccount(args.outboxItem),
        emitter: whAccs.wormholeEmitter,
        transceiver: this.pdas.registeredTransceiver(this.program.programId),
        wormhole: {
          bridge: whAccs.wormholeBridge,
          feeCollector: whAccs.wormholeFeeCollector,
          sequence: whAccs.wormholeSequence,
          program: this.core.address,
        },
      })
      .instruction();
  }

  async createReceiveWormholeMessageInstruction(
    payer: PublicKey,
    wormholeNTT: WormholeNttTransceiver.VAA
  ): Promise<TransactionInstruction> {
    const config = await this.getConfig();
    if (config.paused) throw new Error("Contract is paused");

    const nttMessage = wormholeNTT.payload.nttManagerPayload;
    const emitterChain = wormholeNTT.emitterChain;
    return await this.program.methods
      .receiveWormholeMessage()
      .accounts({
        payer: payer,
        config: { config: this.pdas.configAccount() },
        peer: this.pdas.transceiverPeerAccount(emitterChain),
        vaa: utils.derivePostedVaaKey(
          this.core.address,
          Buffer.from(wormholeNTT.hash)
        ),
        transceiverMessage: this.pdas.transceiverMessageAccount(
          emitterChain,
          nttMessage.id
        ),
      })
      .instruction();
  }

  async createRedeemInstruction(
    payer: PublicKey,
    wormholeNTT: WormholeNttTransceiver.VAA
  ): Promise<TransactionInstruction> {
    const config = await this.getConfig();
    if (config.paused) throw new Error("Contract is paused");

    const nttMessage = wormholeNTT.payload.nttManagerPayload;
    const emitterChain = wormholeNTT.emitterChain;

    const nttManagerPeer = this.pdas.peerAccount(emitterChain);
    const inboxRateLimit = this.pdas.inboxRateLimitAccount(emitterChain);
    const inboxItem = this.pdas.inboxItemAccount(emitterChain, nttMessage);

    return await this.program.methods
      .redeem({})
      .accounts({
        payer: payer,
        config: this.pdas.configAccount(),
        peer: nttManagerPeer,
        transceiverMessage: this.pdas.transceiverMessageAccount(
          emitterChain,
          nttMessage.id
        ),
        transceiver: this.pdas.registeredTransceiver(this.program.programId),
        mint: config.mint,
        inboxItem,
        inboxRateLimit,
        outboxRateLimit: this.pdas.outboxRateLimitAccount(),
      })
      .instruction();
  }

  async createReleaseInboundMintInstruction(args: {
    payer: PublicKey;
    chain: Chain;
    nttMessage: Ntt.Message;
    revertOnDelay: boolean;
    recipient?: PublicKey;
  }): Promise<TransactionInstruction> {
    const config = await this.getConfig();
    if (config.paused) throw new Error("Contract is paused");

    const inboxItem = this.pdas.inboxItemAccount(args.chain, args.nttMessage);

    const recipientAddress =
      args.recipient ??
      (await this.getInboundQueuedTransfer(
        args.chain,
        args.nttMessage
      ))!.recipient
        .toNative(this.chain)
        .unwrap();

    return await this.program.methods
      .releaseInboundMint({
        revertOnDelay: args.revertOnDelay,
      })
      .accounts({
        common: {
          payer: args.payer,
          config: { config: this.pdas.configAccount() },
          inboxItem,
          recipient: getAssociatedTokenAddressSync(
            config.mint,
            recipientAddress
          ),
          mint: config.mint,
          tokenAuthority: this.pdas.tokenAuthority(),
        },
      })
      .instruction();
  }

  async createReleaseInboundUnlockInstruction(args: {
    payer: PublicKey;
    chain: Chain;
    nttMessage: Ntt.Message;
    revertOnDelay: boolean;
    recipient?: PublicKey;
  }): Promise<TransactionInstruction> {
    const config = await this.getConfig();
    if (config.paused) throw new Error("Contract is paused");

    const recipientAddress =
      args.recipient ??
      (await this.getInboundQueuedTransfer(
        args.chain,
        args.nttMessage
      ))!.recipient
        .toNative(this.chain)
        .unwrap();

    const inboxItem = this.pdas.inboxItemAccount(args.chain, args.nttMessage);

    return await this.program.methods
      .releaseInboundUnlock({
        revertOnDelay: args.revertOnDelay,
      })
      .accounts({
        common: {
          payer: args.payer,
          config: { config: this.pdas.configAccount() },
          inboxItem: inboxItem,
          recipient: getAssociatedTokenAddressSync(
            config.mint,
            recipientAddress
          ),
          mint: config.mint,
          tokenAuthority: this.pdas.tokenAuthority(),
        },
        custody: config.custody,
      })
      .instruction();
  }

  async custodyAccountAddress(mint: PublicKey): Promise<PublicKey> {
    return associatedAddress({
      mint: mint,
      owner: this.pdas.tokenAuthority(),
    });
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

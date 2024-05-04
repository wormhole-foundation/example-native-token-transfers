import { BN, Program } from "@coral-xyz/anchor";
import * as splToken from "@solana/spl-token";
import {
  AccountMeta,
  Commitment,
  Connection,
  Keypair,
  PublicKey,
  PublicKeyInitData,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  TransactionMessage,
  VersionedTransaction,
} from "@solana/web3.js";
import {
  Chain,
  ChainAddress,
  ChainId,
  VAA,
  deserializeLayout,
  encoding,
  keccak256,
  rpc,
  toChain,
  toChainId,
} from "@wormhole-foundation/sdk-connect";

import { Ntt } from "@wormhole-foundation/sdk-definitions-ntt";

import { getAssociatedTokenAddressSync } from "@solana/spl-token";
import { SolanaTransaction } from "@wormhole-foundation/sdk-solana";
import { utils } from "@wormhole-foundation/sdk-solana-core";
import { programVersionLayout } from "../sdk/utils.js";
import {
  IdlVersion,
  IdlVersions,
  NttBindings,
  getNttProgram,
} from "./bindings.js";
import { chainToBytes, derivePda } from "./utils.js";

export namespace NTT {
  export interface TransferArgs {
    amount: BN;
    recipientChain: { id: ChainId };
    recipientAddress: number[];
    shouldQueue: boolean;
  }

  export function transferArgs(
    amount: bigint,
    recipient: ChainAddress,
    shouldQueue: boolean
  ): TransferArgs {
    return {
      amount: new BN(amount.toString()),
      recipientChain: { id: toChainId(recipient.chain) },
      recipientAddress: Array.from(
        recipient.address.toUniversalAddress().toUint8Array()
      ),
      shouldQueue: shouldQueue,
    };
  }

  export type Pdas = ReturnType<typeof pdas>;
  export const pdas = (programId: PublicKeyInitData) => {
    const configAccount = (): PublicKey => derivePda("config", programId);
    const emitterAccount = (): PublicKey => derivePda("emitter", programId);
    const inboxRateLimitAccount = (chain: Chain): PublicKey =>
      derivePda(["inbox_rate_limit", chainToBytes(chain)], programId);
    const inboxItemAccount = (
      chain: Chain,
      nttMessage: Ntt.Message
    ): PublicKey =>
      derivePda(
        ["inbox_item", Ntt.messageDigest(chain, nttMessage)],
        programId
      );
    const outboxRateLimitAccount = (): PublicKey =>
      derivePda("outbox_rate_limit", programId);
    const tokenAuthority = (): PublicKey =>
      derivePda("token_authority", programId);
    const peerAccount = (chain: Chain): PublicKey =>
      derivePda(["peer", chainToBytes(chain)], programId);
    const transceiverPeerAccount = (chain: Chain): PublicKey =>
      derivePda(["transceiver_peer", chainToBytes(chain)], programId);
    const registeredTransceiver = (transceiver: PublicKey): PublicKey =>
      derivePda(["registered_transceiver", transceiver.toBytes()], programId);
    const transceiverMessageAccount = (
      chain: Chain,
      id: Uint8Array
    ): PublicKey =>
      derivePda(["transceiver_message", chainToBytes(chain), id], programId);
    const wormholeMessageAccount = (outboxItem: PublicKey): PublicKey =>
      derivePda(["message", outboxItem.toBytes()], programId);
    const lutAccount = (): PublicKey => derivePda("lut", programId);
    const lutAuthority = (): PublicKey => derivePda("lut_authority", programId);
    const sessionAuthority = (
      sender: PublicKey,
      args: TransferArgs
    ): PublicKey =>
      derivePda(
        [
          "session_authority",
          sender.toBytes(),
          keccak256(
            encoding.bytes.concat(
              encoding.bytes.zpad(new Uint8Array(args.amount.toBuffer()), 8),
              chainToBytes(args.recipientChain.id),
              new Uint8Array(args.recipientAddress),
              new Uint8Array([args.shouldQueue ? 1 : 0])
            )
          ),
        ],
        programId
      );

    // TODO: memoize?
    return {
      configAccount,
      outboxRateLimitAccount,
      inboxRateLimitAccount,
      inboxItemAccount,
      sessionAuthority,
      tokenAuthority,
      emitterAccount,
      wormholeMessageAccount,
      peerAccount,
      transceiverPeerAccount,
      transceiverMessageAccount,
      registeredTransceiver,
      lutAccount,
      lutAuthority,
    };
  };

  export async function getVersion(
    connection: Connection,
    programId: PublicKey,
    sender?: PublicKey
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

    if (!sender) {
      const address =
        connection.rpcEndpoint === rpc.rpcAddress("Devnet", "Solana")
          ? "6sbzC1eH4FTujJXWj51eQe25cYvr4xfXbJ1vAj7j2k5J" // The CI pubkey, funded on local network
          : "Hk3SdYTJFpawrvRz4qRztuEt2SqoCG7BGj2yJfDJSFbJ"; // The default pubkey is funded on mainnet and devnet we need a funded account to simulate the transaction below
      sender = new PublicKey(address);
    }

    const program = getNttProgram(connection, programId.toString(), "1.0.0");

    const ix = await program.methods.version().accountsStrict({}).instruction();
    const latestBlockHash =
      await program.provider.connection.getLatestBlockhash();
    const msg = new TransactionMessage({
      payerKey: sender,
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

  export async function createTransferBurnInstruction(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    config: NttBindings.Config<IdlVersion>,
    args: {
      payer: PublicKey;
      from: PublicKey;
      fromAuthority: PublicKey;
      transferArgs: TransferArgs;
      outboxItem: PublicKey;
    },
    pdas?: Pdas
  ): Promise<TransactionInstruction> {
    pdas = pdas ?? NTT.pdas(program.programId);

    const recipientChain = toChain(args.transferArgs.recipientChain.id);
    const transferIx = await program.methods
      .transferBurn(args.transferArgs)
      .accountsStrict({
        common: {
          payer: args.payer,
          config: { config: pdas.configAccount() },
          mint: config.mint,
          from: args.from,
          tokenProgram: config.tokenProgram,
          outboxItem: args.outboxItem,
          outboxRateLimit: pdas.outboxRateLimitAccount(),
          custody: await custodyAccountAddress(pdas, config),
          systemProgram: SystemProgram.programId,
        },
        peer: pdas.peerAccount(recipientChain),
        inboxRateLimit: pdas.inboxRateLimitAccount(recipientChain),
        sessionAuthority: pdas.sessionAuthority(
          args.fromAuthority,
          args.transferArgs
        ),
        tokenAuthority: pdas.tokenAuthority(),
      })
      .instruction();

    const mintInfo = await splToken.getMint(
      program.provider.connection,
      config.mint,
      undefined,
      config.tokenProgram
    );
    const transferHook = splToken.getTransferHook(mintInfo);

    if (transferHook) {
      const source = args.from;
      const mint = config.mint;
      const destination = await custodyAccountAddress(pdas, config);
      const owner = pdas.sessionAuthority(
        args.fromAuthority,
        args.transferArgs
      );
      await addExtraAccountMetasForExecute(
        program.provider.connection,
        transferIx,
        transferHook.programId,
        source,
        mint,
        destination,
        owner,
        // TODO(csongor): compute the amount that's passed into transfer.
        // Leaving this 0 is fine unless the transfer hook accounts addresses
        // depend on the amount (which is unlikely).
        // If this turns out to be the case, the amount to put here is the
        // untrimmed amount after removing dust.
        0
      );
    }

    return transferIx;
  }

  /**
   * Creates a transfer_lock instruction. The `payer`, `fromAuthority`, and `outboxItem`
   * arguments must sign the transaction
   */
  export async function createTransferLockInstruction(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    config: NttBindings.Config<IdlVersion>,
    args: {
      payer: PublicKey;
      from: PublicKey;
      fromAuthority: PublicKey;
      transferArgs: NTT.TransferArgs;
      outboxItem: PublicKey;
    },
    pdas?: Pdas
  ): Promise<TransactionInstruction> {
    if (config.paused) throw new Error("Contract is paused");

    pdas = pdas ?? NTT.pdas(program.programId);

    const chain = toChain(args.transferArgs.recipientChain.id);

    const transferIx = await program.methods
      .transferLock(args.transferArgs)
      .accounts({
        common: {
          payer: args.payer,
          config: { config: pdas.configAccount() },
          mint: config.mint,
          from: args.from,
          tokenProgram: config.tokenProgram,
          outboxItem: args.outboxItem,
          outboxRateLimit: pdas.outboxRateLimitAccount(),
          custody: await custodyAccountAddress(pdas, config),
        },
        peer: pdas.peerAccount(chain),
        inboxRateLimit: pdas.inboxRateLimitAccount(chain),
        sessionAuthority: pdas.sessionAuthority(
          args.fromAuthority,
          args.transferArgs
        ),
      })
      .instruction();

    const mintInfo = await splToken.getMint(
      program.provider.connection,
      config.mint,
      undefined,
      config.tokenProgram
    );
    const transferHook = splToken.getTransferHook(mintInfo);

    if (transferHook) {
      const source = args.from;
      const destination = await custodyAccountAddress(pdas, config);
      const owner = pdas.sessionAuthority(
        args.fromAuthority,
        args.transferArgs
      );
      await addExtraAccountMetasForExecute(
        program.provider.connection,
        transferIx,
        transferHook.programId,
        source,
        config.mint,
        destination,
        owner,
        // TODO(csongor): compute the amount that's passed into transfer.
        // Leaving this 0 is fine unless the transfer hook accounts addresses
        // depend on the amount (which is unlikely).
        // If this turns out to be the case, the amount to put here is the
        // untrimmed amount after removing dust.
        0
      );
    }

    return transferIx;
  }

  /**
   * Creates a release_outbound instruction. The `payer` needs to sign the transaction.
   */
  export async function createReleaseOutboundInstruction(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    args: {
      wormholeId: PublicKey;
      payer: PublicKey;
      outboxItem: PublicKey;
      revertOnDelay: boolean;
    },
    pdas?: Pdas
  ): Promise<TransactionInstruction> {
    pdas = pdas ?? NTT.pdas(program.programId);

    const whAccs = utils.getWormholeDerivedAccounts(
      program.programId,
      args.wormholeId
    );

    return await program.methods
      .releaseWormholeOutbound({
        revertOnDelay: args.revertOnDelay,
      })
      .accounts({
        payer: args.payer,
        config: { config: pdas.configAccount() },
        outboxItem: args.outboxItem,
        wormholeMessage: pdas.wormholeMessageAccount(args.outboxItem),
        emitter: whAccs.wormholeEmitter,
        transceiver: pdas.registeredTransceiver(program.programId),
        wormhole: {
          bridge: whAccs.wormholeBridge,
          feeCollector: whAccs.wormholeFeeCollector,
          sequence: whAccs.wormholeSequence,
          program: args.wormholeId,
        },
      })
      .instruction();
  }

  // TODO: document that if recipient is provided, then the instruction can be
  // created before the inbox item is created (i.e. they can be put in the same tx)
  export async function createReleaseInboundMintInstruction(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    config: NttBindings.Config<IdlVersion>,
    args: {
      payer: PublicKey;
      chain: Chain;
      nttMessage: Ntt.Message;
      revertOnDelay: boolean;
      recipient?: PublicKey;
    },
    pdas?: Pdas
  ): Promise<TransactionInstruction> {
    pdas = pdas ?? NTT.pdas(program.programId);

    const recipientAddress =
      args.recipient ??
      (await getInboxItem(program, args.chain, args.nttMessage))
        .recipientAddress;

    const transferIx = await program.methods
      .releaseInboundMint({
        revertOnDelay: args.revertOnDelay,
      })
      .accountsStrict({
        common: {
          payer: args.payer,
          config: { config: pdas.configAccount() },
          inboxItem: pdas.inboxItemAccount(args.chain, args.nttMessage),
          recipient: getAssociatedTokenAddressSync(
            config.mint,
            recipientAddress,
            true,
            config.tokenProgram
          ),
          mint: config.mint,
          tokenAuthority: pdas.tokenAuthority(),
          tokenProgram: config.tokenProgram,
          custody: await custodyAccountAddress(pdas, config),
        },
      })
      .instruction();

    const mintInfo = await splToken.getMint(
      program.provider.connection,
      config.mint,
      undefined,
      config.tokenProgram
    );
    const transferHook = splToken.getTransferHook(mintInfo);

    if (transferHook) {
      const source = await custodyAccountAddress(pdas, config);
      const mint = config.mint;
      const destination = getAssociatedTokenAddressSync(
        mint,
        recipientAddress,
        true,
        config.tokenProgram
      );
      const owner = pdas.tokenAuthority();
      await addExtraAccountMetasForExecute(
        program.provider.connection,
        transferIx,
        transferHook.programId,
        source,
        mint,
        destination,
        owner,
        // TODO(csongor): compute the amount that's passed into transfer.
        // Leaving this 0 is fine unless the transfer hook accounts addresses
        // depend on the amount (which is unlikely).
        // If this turns out to be the case, the amount to put here is the
        // untrimmed amount after removing dust.
        0
      );
    }

    return transferIx;
  }

  export async function createReleaseInboundUnlockInstruction(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    config: NttBindings.Config<IdlVersion>,
    args: {
      payer: PublicKey;
      chain: Chain;
      nttMessage: Ntt.Message;
      revertOnDelay: boolean;
      recipient?: PublicKey;
    },
    pdas?: Pdas
  ) {
    const recipientAddress =
      args.recipient ??
      (await NTT.getInboxItem(program, args.chain, args.nttMessage))
        .recipientAddress;

    pdas = pdas ?? NTT.pdas(program.programId);

    const transferIx = await program.methods
      .releaseInboundUnlock({
        revertOnDelay: args.revertOnDelay,
      })
      .accountsStrict({
        common: {
          payer: args.payer,
          config: { config: pdas.configAccount() },
          inboxItem: pdas.inboxItemAccount(args.chain, args.nttMessage),
          recipient: getAssociatedTokenAddressSync(
            config.mint,
            recipientAddress,
            true,
            config.tokenProgram
          ),
          mint: config.mint,
          tokenAuthority: pdas.tokenAuthority(),
          tokenProgram: config.tokenProgram,
          custody: await custodyAccountAddress(pdas, config),
        },
        custody: "",
      })
      .instruction();

    const mintInfo = await splToken.getMint(
      program.provider.connection,
      config.mint,
      undefined,
      config.tokenProgram
    );
    const transferHook = splToken.getTransferHook(mintInfo);

    if (transferHook) {
      const source = await custodyAccountAddress(pdas, config);
      const mint = config.mint;
      const destination = getAssociatedTokenAddressSync(
        mint,
        recipientAddress,
        true,
        config.tokenProgram
      );
      const owner = pdas.tokenAuthority();
      await addExtraAccountMetasForExecute(
        program.provider.connection,
        transferIx,
        transferHook.programId,
        source,
        mint,
        destination,
        owner,
        // TODO(csongor): compute the amount that's passed into transfer.
        // Leaving this 0 is fine unless the transfer hook accounts addresses
        // depend on the amount (which is unlikely).
        // If this turns out to be the case, the amount to put here is the
        // untrimmed amount after removing dust.
        0
      );
    }

    return transferIx;
  }

  export async function createSetPeerInstruction(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    args: {
      payer: PublicKey;
      owner: PublicKey;
      chain: Chain;
      address: ArrayLike<number>;
      limit: BN;
      tokenDecimals: number;
    },
    pdas?: Pdas
  ) {
    pdas = pdas ?? NTT.pdas(program.programId);
    return await program.methods
      .setPeer({
        chainId: { id: toChainId(args.chain) },
        address: Array.from(args.address),
        limit: args.limit,
        tokenDecimals: args.tokenDecimals,
      })
      .accounts({
        payer: args.payer,
        owner: args.owner,
        config: pdas.configAccount(),
        peer: pdas.peerAccount(args.chain),
        inboxRateLimit: pdas.inboxRateLimitAccount(args.chain),
      })
      .instruction();
  }

  export async function setWormholeTransceiverPeer(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    args: {
      wormholeId: PublicKey;
      payer: PublicKey;
      owner: PublicKey;
      chain: Chain;
      address: ArrayLike<number>;
    },
    pdas?: Pdas
  ) {
    pdas = pdas ?? NTT.pdas(program.programId);
    const ix = await program.methods
      .setWormholePeer({
        chainId: { id: toChainId(args.chain) },
        address: Array.from(args.address),
      })
      .accounts({
        payer: args.payer,
        owner: args.owner,
        config: pdas.configAccount(),
        peer: pdas.transceiverPeerAccount(args.chain),
      })
      .instruction();

    const wormholeMessage = Keypair.generate();
    const whAccs = utils.getWormholeDerivedAccounts(
      program.programId,
      args.wormholeId
    );

    const broadcastIx = await program.methods
      .broadcastWormholePeer({ chainId: toChainId(args.chain) })
      .accounts({
        payer: args.payer,
        config: pdas.configAccount(),
        peer: pdas.transceiverPeerAccount(args.chain),
        wormholeMessage: wormholeMessage.publicKey,
        emitter: pdas.emitterAccount(),
        wormhole: {
          bridge: whAccs.wormholeBridge,
          feeCollector: whAccs.wormholeFeeCollector,
          sequence: whAccs.wormholeSequence,
          program: args.wormholeId,
        },
      })
      .instruction();

    return {
      transaction: new Transaction().add(ix, broadcastIx),
      signers: [args.payer, args.owner, wormholeMessage],
    } as SolanaTransaction;
  }

  export async function registerTransceiver(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    config: NttBindings.Config<IdlVersion>,
    args: {
      wormholeId: PublicKey;
      payer: PublicKey;
      owner: PublicKey;
      transceiver: PublicKey;
    },
    pdas?: Pdas
  ) {
    pdas = pdas ?? NTT.pdas(program.programId);
    const ix = await program.methods
      .registerTransceiver()
      .accounts({
        payer: args.payer,
        owner: args.owner,
        config: pdas.configAccount(),
        transceiver: args.transceiver,
        registeredTransceiver: pdas.registeredTransceiver(args.transceiver),
      })
      .instruction();

    const wormholeMessage = Keypair.generate();
    const whAccs = utils.getWormholeDerivedAccounts(
      program.programId,
      args.wormholeId
    );
    const broadcastIx = await program.methods
      .broadcastWormholeId()
      .accounts({
        payer: args.payer,
        config: pdas.configAccount(),
        mint: config.mint,
        wormholeMessage: wormholeMessage.publicKey,
        emitter: pdas.emitterAccount(),
        wormhole: {
          bridge: whAccs.wormholeBridge,
          feeCollector: whAccs.wormholeFeeCollector,
          sequence: whAccs.wormholeSequence,
          program: args.wormholeId,
        },
      })
      .instruction();

    return {
      transaction: new Transaction().add(ix, broadcastIx),
      signers: [args.payer, args.owner, wormholeMessage],
    };
  }

  export async function createSetOuboundLimitInstruction(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    args: {
      owner: PublicKey;
      chain: Chain;
      limit: BN;
    },
    pdas?: Pdas
  ) {
    pdas = pdas ?? NTT.pdas(program.programId);
    return await program.methods
      .setOutboundLimit({
        limit: args.limit,
      })
      .accounts({
        owner: args.owner,
        config: pdas.configAccount(),
        rateLimit: pdas.outboxRateLimitAccount(),
      })
      .instruction();
  }

  export async function setInboundLimit(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    args: {
      owner: PublicKey;
      chain: Chain;
      limit: BN;
    },
    pdas?: Pdas
  ) {
    pdas = pdas ?? NTT.pdas(program.programId);
    return await program.methods
      .setInboundLimit({
        chainId: { id: toChainId(args.chain) },
        limit: args.limit,
      })
      .accounts({
        owner: args.owner,
        config: pdas.configAccount(),
        rateLimit: pdas.inboxRateLimitAccount(args.chain),
      })
      .instruction();
  }

  export async function createReceiveWormholeMessageInstruction(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    args: {
      wormholeId: PublicKey;
      payer: PublicKey;
      vaa: VAA<"Ntt:WormholeTransfer">;
    },
    pdas?: Pdas
  ): Promise<TransactionInstruction> {
    pdas = pdas ?? NTT.pdas(program.programId);

    const wormholeNTT = args.vaa;
    const nttMessage = wormholeNTT.payload.nttManagerPayload;
    const chain = wormholeNTT.emitterChain;

    const transceiverPeer = pdas.transceiverPeerAccount(chain);

    return await program.methods
      .receiveWormholeMessage()
      .accounts({
        payer: args.payer,
        config: { config: pdas.configAccount() },
        peer: transceiverPeer,
        vaa: utils.derivePostedVaaKey(
          args.wormholeId,
          Buffer.from(wormholeNTT.hash)
        ),
        transceiverMessage: pdas.transceiverMessageAccount(
          chain,
          nttMessage.id
        ),
      })
      .instruction();
  }
  export async function createRedeemInstruction(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    config: NttBindings.Config<IdlVersion>,
    args: {
      payer: PublicKey;
      vaa: VAA<"Ntt:WormholeTransfer">;
    },
    pdas?: Pdas
  ): Promise<TransactionInstruction> {
    pdas = pdas ?? NTT.pdas(program.programId);

    const wormholeNTT = args.vaa;
    const nttMessage = wormholeNTT.payload.nttManagerPayload;
    const chain = wormholeNTT.emitterChain;

    return await program.methods
      .redeem({})
      .accounts({
        payer: args.payer,
        config: pdas.configAccount(),
        peer: pdas.peerAccount(chain),
        transceiverMessage: pdas.transceiverMessageAccount(
          chain,
          nttMessage.id
        ),
        transceiver: pdas.registeredTransceiver(program.programId),
        mint: config.mint,
        inboxItem: pdas.inboxItemAccount(chain, nttMessage),
        inboxRateLimit: pdas.inboxRateLimitAccount(chain),
        outboxRateLimit: pdas.outboxRateLimitAccount(),
      })
      .instruction();
  }

  // Account access

  /**
   * Fetches the Config account from the contract.
   *
   * @param config If provided, the config is just returned without making a
   *               network request. This is handy in case multiple config
   *               accessor functions are used, the config can just be queried
   *               once and passed around.
   */
  export async function getConfig(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    pdas: Pdas
  ): Promise<NttBindings.Config<IdlVersion>> {
    return await program.account.config.fetch(pdas.configAccount());
  }

  export async function getInboxItem(
    program: Program<NttBindings.NativeTokenTransfer<IdlVersion>>,
    fromChain: Chain,
    nttMessage: Ntt.Message
  ): Promise<NttBindings.InboxItem<IdlVersion>> {
    return await program.account.inboxItem.fetch(
      NTT.pdas(program.programId).inboxItemAccount(fromChain, nttMessage)
    );
  }

  /**
   * Returns the address of the custody account. If the config is available
   * (i.e. the program is initialised), the mint is derived from the config.
   * Otherwise, the mint must be provided.
   */
  export async function custodyAccountAddress(
    pdas: Pdas,
    configOrMint: NttBindings.Config<IdlVersion> | PublicKey,
    tokenProgram = splToken.TOKEN_PROGRAM_ID
  ): Promise<PublicKey> {
    if (configOrMint instanceof PublicKey) {
      return splToken.getAssociatedTokenAddress(
        configOrMint,
        pdas.tokenAuthority(),
        true,
        tokenProgram
      );
    } else {
      return splToken.getAssociatedTokenAddress(
        configOrMint.mint,
        pdas.tokenAuthority(),
        true,
        configOrMint.tokenProgram
      );
    }
  }
}

/**
 * TODO: this is copied from @solana/spl-token, because the most recent released
 * version (0.4.3) is broken (does object equality instead of structural on the pubkey)
 *
 * this version fixes that error, looks like it's also fixed on main:
 * https://github.com/solana-labs/solana-program-library/blob/ad4eb6914c5e4288ad845f29f0003cd3b16243e7/token/js/src/extensions/transferHook/instructions.ts#L208
 */
async function addExtraAccountMetasForExecute(
  connection: Connection,
  instruction: TransactionInstruction,
  programId: PublicKey,
  source: PublicKey,
  mint: PublicKey,
  destination: PublicKey,
  owner: PublicKey,
  amount: number | bigint,
  commitment?: Commitment
) {
  const validateStatePubkey = splToken.getExtraAccountMetaAddress(
    mint,
    programId
  );
  const validateStateAccount = await connection.getAccountInfo(
    validateStatePubkey,
    commitment
  );
  if (validateStateAccount == null) {
    return instruction;
  }
  const validateStateData = splToken.getExtraAccountMetas(validateStateAccount);

  // Check to make sure the provided keys are in the instruction
  if (
    ![source, mint, destination, owner].every((key) =>
      instruction.keys.some((meta) => meta.pubkey.equals(key))
    )
  ) {
    throw new Error("Missing required account in instruction");
  }

  const executeInstruction = splToken.createExecuteInstruction(
    programId,
    source,
    mint,
    destination,
    owner,
    validateStatePubkey,
    BigInt(amount)
  );

  for (const extraAccountMeta of validateStateData) {
    executeInstruction.keys.push(
      deEscalateAccountMeta(
        await splToken.resolveExtraAccountMeta(
          connection,
          extraAccountMeta,
          executeInstruction.keys,
          executeInstruction.data,
          executeInstruction.programId
        ),
        executeInstruction.keys
      )
    );
  }

  // Add only the extra accounts resolved from the validation state
  instruction.keys.push(...executeInstruction.keys.slice(5));

  // Add the transfer hook program ID and the validation state account
  instruction.keys.push({
    pubkey: programId,
    isSigner: false,
    isWritable: false,
  });
  instruction.keys.push({
    pubkey: validateStatePubkey,
    isSigner: false,
    isWritable: false,
  });
}

// TODO: delete (see above)
function deEscalateAccountMeta(
  accountMeta: AccountMeta,
  accountMetas: AccountMeta[]
): AccountMeta {
  const maybeHighestPrivileges = accountMetas
    .filter((x) => x.pubkey.equals(accountMeta.pubkey))
    .reduce<{ isSigner: boolean; isWritable: boolean } | undefined>(
      (acc, x) => {
        if (!acc) return { isSigner: x.isSigner, isWritable: x.isWritable };
        return {
          isSigner: acc.isSigner || x.isSigner,
          isWritable: acc.isWritable || x.isWritable,
        };
      },
      undefined
    );
  if (maybeHighestPrivileges) {
    const { isSigner, isWritable } = maybeHighestPrivileges;
    if (!isSigner && isSigner !== accountMeta.isSigner) {
      accountMeta.isSigner = false;
    }
    if (!isWritable && isWritable !== accountMeta.isWritable) {
      accountMeta.isWritable = false;
    }
  }
  return accountMeta;
}

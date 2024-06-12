import { type ChainName, toChainId, coalesceChainId, type ChainId, type SignedVaa } from '@certusone/wormhole-sdk'
import { serializeLayout, toChainId as SDKv2toChainId } from '@wormhole-foundation/sdk-base'
import {
  deserialize,
} from '@wormhole-foundation/sdk-definitions'

import {
  type NttManagerMessage,
  nttManagerMessageLayout,
  nativeTokenTransferLayout
} from './nttLayout'
import { derivePostedVaaKey, getWormholeDerivedAccounts } from '@certusone/wormhole-sdk/lib/cjs/solana/wormhole'
import { BN, translateError, type IdlAccounts, Program, web3, } from '@coral-xyz/anchor'
import { getAssociatedTokenAddressSync } from '@solana/spl-token'
import {
  PublicKey, Keypair,
  type TransactionInstruction,
  Transaction,
  sendAndConfirmTransaction,
  type TransactionSignature,
  type Connection,
  SystemProgram,
  TransactionMessage,
  VersionedTransaction,
  Commitment,
  AccountMeta,
  AddressLookupTableProgram,
  AddressLookupTableAccount
} from '@solana/web3.js'
import { Keccak } from 'sha3'
import { type ExampleNativeTokenTransfers as RawExampleNativeTokenTransfers } from '../../idl/ts/example_native_token_transfers'
import { BPF_LOADER_UPGRADEABLE_PROGRAM_ID, programDataAddress, chainIdToBeBytes, derivePda } from './utils'
import * as splToken from '@solana/spl-token';
import IDL from '../../idl/json/example_native_token_transfers.json';

export * from './utils/wormhole'

export const nttMessageLayout = nttManagerMessageLayout(nativeTokenTransferLayout);
export type NttMessage = NttManagerMessage<typeof nativeTokenTransferLayout>;

// This is a workaround for the fact that the anchor idl doesn't support generics
// yet. This type is used to remove the generics from the idl types.
type OmitGenerics<T> = {
  [P in keyof T]: T[P] extends Record<"generics", any>
  ? never
  : T[P] extends object
  ? OmitGenerics<T[P]>
  : T[P];
};

export type ExampleNativeTokenTransfers = OmitGenerics<RawExampleNativeTokenTransfers>

export type Config = IdlAccounts<ExampleNativeTokenTransfers>['config']
export type InboxItem = IdlAccounts<ExampleNativeTokenTransfers>['inboxItem']

export interface TransferArgs {
  amount: BN
  recipientChain: { id: ChainId }
  recipientAddress: number[]
  shouldQueue: boolean
}

export const NTT_PROGRAM_IDS = [
  "nttiK1SepaQt6sZ4WGW5whvc9tEnGXGxuKeptcQPCcS",
  "NTTManager111111111111111111111111111111111",
  "NTTManager222222222222222222222222222222222",
] as const;

export const WORMHOLE_PROGRAM_IDS = [
  "worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth", // mainnet
  "3u8hJUVTA4jH1wYAyUur7FFZVQ8H635K3tSHHF4ssjQ5", // testnet
  "Bridge1p5gheXUvJ6jGWGeCsgPKgnE3YgdGKRVCMY9o", // tilt
] as const;

export type NttProgramId = (typeof NTT_PROGRAM_IDS)[number];
export type WormholeProgramId = (typeof WORMHOLE_PROGRAM_IDS)[number];

export class NTT {
  readonly program: Program<ExampleNativeTokenTransfers>
  readonly wormholeId: PublicKey
  // mapping from error code to error message. Used for prettifying error messages
  private readonly errors: Map<number, string>
  addressLookupTable: web3.AddressLookupTableAccount | null = null

  constructor(connection: Connection, args: { nttId: NttProgramId, wormholeId: WormholeProgramId }) {
    // TODO: initialise a new Program here with a passed in Connection
    this.program = new Program(IDL as any, new PublicKey(args.nttId), { connection });
    this.wormholeId = new PublicKey(args.wormholeId)
    this.errors = this.processErrors()
  }

  // The `translateError` function expects this format, but the idl gives us a
  // different one, so we preprocess the idl and store the expected format.
  // NOTE: I'm sure there's a function within anchor that does this, but I
  // couldn't find it.
  private processErrors(): Map<number, string> {
    const errors = this.program.idl.errors
    const result: Map<number, string> = new Map<number, string>()
    errors.forEach(entry => result.set(entry.code, entry.msg))
    return result
  }

  // Account addresses

  private derivePda(seeds: Parameters<typeof derivePda>[0]): PublicKey {
    return derivePda(seeds, this.program.programId)
  }

  configAccountAddress(): PublicKey {
    return this.derivePda('config')
  }

  lutAccountAddress(): PublicKey {
    return this.derivePda('lut')
  }

  lutAuthorityAddress(): PublicKey {
    return this.derivePda('lut_authority')
  }

  outboxRateLimitAccountAddress(): PublicKey {
    return this.derivePda('outbox_rate_limit')
  }

  inboxRateLimitAccountAddress(chain: ChainName | ChainId): PublicKey {
    const chainId = coalesceChainId(chain)
    return this.derivePda(['inbox_rate_limit', chainIdToBeBytes(chainId)])
  }

  inboxItemAccountAddress(chain: ChainName | ChainId, nttMessage: NttMessage): PublicKey {
    const chainId = coalesceChainId(chain)
    const serialized = Buffer.from(
      serializeLayout(nttManagerMessageLayout(nativeTokenTransferLayout), nttMessage)
    )
    const hasher = new Keccak(256) //TODO replace with keccak256 from SDKv2
    hasher.update(Buffer.from(chainIdToBeBytes(chainId)))
    hasher.update(serialized)
    return this.derivePda(['inbox_item', hasher.digest()])
  }

  sessionAuthorityAddress(sender: PublicKey, args: TransferArgs): PublicKey {
    const { amount, recipientChain, recipientAddress, shouldQueue } = args
    const serialized = Buffer.concat([
      amount.toArrayLike(Buffer, 'be', 8),
      Buffer.from(new BN(recipientChain.id).toArrayLike(Buffer, 'be', 2)),
      Buffer.from(new Uint8Array(recipientAddress)),
      Buffer.from([shouldQueue ? 1 : 0])
    ])
    const hasher = new Keccak(256)
    hasher.update(serialized)
    return this.derivePda(['session_authority', sender.toBytes(), hasher.digest()])
  }

  tokenAuthorityAddress(): PublicKey {
    return this.derivePda('token_authority')
  }

  emitterAccountAddress(): PublicKey {
    return this.derivePda('emitter')
  }

  wormholeMessageAccountAddress(outboxItem: PublicKey): PublicKey {
    return this.derivePda(['message', outboxItem.toBytes()])
  }

  peerAccountAddress(chain: ChainName | ChainId): PublicKey {
    const chainId = coalesceChainId(chain)
    return this.derivePda(['peer', chainIdToBeBytes(chainId)])
  }

  transceiverPeerAccountAddress(chain: ChainName | ChainId): PublicKey {
    const chainId = coalesceChainId(chain)
    return this.derivePda(['transceiver_peer', chainIdToBeBytes(chainId)])
  }

  transceiverMessageAccountAddress(chain: ChainName | ChainId, id: Uint8Array): PublicKey {
    const chainId = coalesceChainId(chain)
    if (id.length != 32) {
      throw new Error('id must be 32 bytes')
    }
    return this.derivePda(['transceiver_message', chainIdToBeBytes(chainId), id])
  }

  registeredTransceiverAddress(transceiver: PublicKey): PublicKey {
    return this.derivePda(['registered_transceiver', transceiver.toBytes()])
  }

  // View functions

  async version(pubkey: PublicKey): Promise<string> {
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
    const ix = await this.program.methods.version()
      .accountsStrict({}).instruction()
    const latestBlockHash = await this.program.provider.connection.getLatestBlockhash()

    const msg = new TransactionMessage({
      payerKey: pubkey,
      recentBlockhash: latestBlockHash.blockhash,
      instructions: [ix],
    }).compileToV0Message();

    const tx = new VersionedTransaction(msg);

    const txSimulation =
      await this.program.provider.connection
        .simulateTransaction(tx, {
          sigVerify: false,
        })

    // the return buffer is in base64 and it encodes the string with a 32 bit
    // little endian length prefix.
    const buffer = Buffer.from(txSimulation.value.returnData?.data[0], 'base64')
    const len = buffer.readUInt32LE(0)
    return buffer.subarray(4, len + 4).toString()
  }

  // Instructions

  async initialize(args: {
    payer: Keypair
    owner: Keypair
    chain: ChainName
    mint: PublicKey
    outboundLimit: BN
    mode: 'burning' | 'locking'
  }): Promise<void> {
    const mode: any =
      args.mode === 'burning'
        ? { burning: {} }
        : { locking: {} }
    const chainId = toChainId(args.chain)
    const mintInfo = await this.program.provider.connection.getAccountInfo(args.mint)
    if (mintInfo === null) {
      throw new Error("Couldn't determine token program. Mint account is null.")
    }
    const tokenProgram = mintInfo.owner
    const ix = await this.program.methods
      .initialize({ chainId, limit: args.outboundLimit, mode })
      .accountsStrict({
        payer: args.payer.publicKey,
        deployer: args.owner.publicKey,
        programData: programDataAddress(this.program.programId),
        config: this.configAccountAddress(),
        mint: args.mint,
        rateLimit: this.outboxRateLimitAccountAddress(),
        tokenProgram,
        tokenAuthority: this.tokenAuthorityAddress(),
        custody: await this.custodyAccountAddress(args.mint, tokenProgram),
        bpfLoaderUpgradeableProgram: BPF_LOADER_UPGRADEABLE_PROGRAM_ID,
        associatedTokenProgram: splToken.ASSOCIATED_TOKEN_PROGRAM_ID,
        systemProgram: SystemProgram.programId,
      }).instruction();
    await this.sendAndConfirmTransaction(new Transaction().add(ix), [args.payer, args.owner], false);
    await this.initializeOrUpdateLUT({ payer: args.payer })
  }

  // This function should be called after each upgrade. If there's nothing to
  // do, it won't actually submit a transaction, so it's cheap to call.
  async initializeOrUpdateLUT(args: {
    payer: Keypair
  }): Promise<AddressLookupTableAccount> {
    // TODO: find a more robust way of fetching a recent slot
    const slot = await this.program.provider.connection.getSlot() - 1

    const [_, lutAddress] = web3.AddressLookupTableProgram.createLookupTable({
      authority: this.lutAuthorityAddress(),
      payer: args.payer.publicKey,
      recentSlot: slot,
    });

    const whAccs = getWormholeDerivedAccounts(this.program.programId, this.wormholeId)
    const config = await this.getConfig()

    const entries = {
       config: this.configAccountAddress(),
       custody: await this.custodyAccountAddress(config),
       tokenProgram: await this.tokenProgram(config),
       mint: await this.mintAccountAddress(config),
       tokenAuthority: this.tokenAuthorityAddress(),
       outboxRateLimit: this.outboxRateLimitAccountAddress(),
       wormhole: {
         bridge: whAccs.wormholeBridge,
         feeCollector: whAccs.wormholeFeeCollector,
         sequence: whAccs.wormholeSequence,
         program: this.wormholeId,
         systemProgram: SystemProgram.programId,
         clock: web3.SYSVAR_CLOCK_PUBKEY,
         rent: web3.SYSVAR_RENT_PUBKEY,
       }
    };

    // collect all pubkeys in entries recursively
    const collectPubkeys = (obj: any): Array<PublicKey> => {
      const pubkeys = new Array<PublicKey>()
      for (const key in obj) {
        const value = obj[key]
        if (value instanceof PublicKey) {
          pubkeys.push(value)
        } else if (typeof value === 'object') {
          pubkeys.push(...collectPubkeys(value, pubkeys))
        }
      }
      return pubkeys
    }
    const pubkeys = collectPubkeys(entries).map(pk => pk.toBase58())

    var existingLut: web3.AddressLookupTableAccount | null = null
    try {
      existingLut = await this.getAddressLookupTable(false)
    } catch {
      // swallow errors here, it just means that lut doesn't exist
    }

    if (existingLut !== null) {
      const existingPubkeys = existingLut.state.addresses?.map(a => a.toBase58()) ?? []

      // if pubkeys contains keys that are not in the existing LUT, we need to
      // add them to the LUT
      const missingPubkeys = pubkeys.filter(pk => !existingPubkeys.includes(pk))

      if (missingPubkeys.length === 0) {
        return existingLut
      }
    }

    const ix = await this.program.methods
      .initializeLut(new BN(slot))
      .accountsStrict({
        payer: args.payer.publicKey,
        authority: this.lutAuthorityAddress(),
        lutAddress,
        lut: this.lutAccountAddress(),
        lutProgram: AddressLookupTableProgram.programId,
        systemProgram: SystemProgram.programId,
        entries
      }).instruction();

    const signers = [args.payer]
    await this.sendAndConfirmTransaction(new Transaction().add(ix), signers, false);

    // NOTE: explicitly invalidate the cache. This is the only operation that
    // modifies the LUT, so this is the only place we need to invalide.
    return this.getAddressLookupTable(false)
  }

  async transfer(args: {
    payer: Keypair
    from: PublicKey
    fromAuthority: Keypair
    amount: BN
    recipientChain: ChainName
    recipientAddress: ArrayLike<number>
    shouldQueue: boolean
    outboxItem?: Keypair
    config?: Config
  }): Promise<PublicKey> {
    const config: Config = await this.getConfig(args.config)

    const outboxItem = args.outboxItem ?? Keypair.generate()

    const txArgs = {
      ...args,
      payer: args.payer.publicKey,
      fromAuthority: args.fromAuthority.publicKey,
      outboxItem: outboxItem.publicKey,
      config
    }

    let transferIx: TransactionInstruction
    if (config.mode.locking != null) {
      transferIx = await this.createTransferLockInstruction(txArgs)
    } else if (config.mode.burning != null) {
      transferIx = await this.createTransferBurnInstruction(txArgs)
    } else {
      // @ts-ignore
      transferIx = exhaustive(config.mode)
    }

    const releaseIx: TransactionInstruction = await this.createReleaseOutboundInstruction({
      payer: args.payer.publicKey,
      outboxItem: outboxItem.publicKey,
      revertOnDelay: !args.shouldQueue
    })

    const signers = [args.payer, args.fromAuthority, outboxItem]

    const transferArgs: TransferArgs = {
      amount: args.amount,
      recipientChain: { id: toChainId(args.recipientChain) },
      recipientAddress: Array.from(args.recipientAddress),
      shouldQueue: args.shouldQueue
    }
    const approveIx = splToken.createApproveInstruction(
      args.from,
      this.sessionAuthorityAddress(args.fromAuthority.publicKey, transferArgs),
      args.fromAuthority.publicKey,
      BigInt(args.amount.toString()),
      [],
      config.tokenProgram
    );
    const tx = new Transaction()
    tx.add(approveIx, transferIx, releaseIx)
    await this.sendAndConfirmTransaction(tx, signers)

    return outboxItem.publicKey
  }

  /**
   * Like `sendAndConfirmTransaction` but parses the anchor error code.
   */
  private async sendAndConfirmTransaction(tx: Transaction, signers: Keypair[], useLut = true): Promise<TransactionSignature> {
    const blockhash = await this.program.provider.connection.getLatestBlockhash()
    const luts: AddressLookupTableAccount[] = []
    if (useLut) {
      luts.push(await this.getAddressLookupTable())
    }

    try {
      const messageV0 = new TransactionMessage({
        payerKey: signers[0].publicKey,
        recentBlockhash: blockhash.blockhash,
        instructions: tx.instructions,
      }).compileToV0Message(luts)

      const transactionV0 = new VersionedTransaction(messageV0)
      transactionV0.sign(signers)

      // The types for this function are wrong -- the type says it doesn't
      // support version transactions, but it does 🤫
      // @ts-ignore
      return await sendAndConfirmTransaction(this.program.provider.connection, transactionV0)
    } catch (err) {
      throw translateError(err, this.errors)
    }
  }

  /**
   * Creates a transfer_burn instruction. The `payer` and `fromAuthority`
   * arguments must sign the transaction
   */
  async createTransferBurnInstruction(args: {
    payer: PublicKey
    from: PublicKey
    fromAuthority: PublicKey
    amount: BN
    recipientChain: ChainName
    recipientAddress: ArrayLike<number>
    outboxItem: PublicKey
    shouldQueue: boolean
    config?: Config
  }): Promise<TransactionInstruction> {
    const config = await this.getConfig(args.config)

    if (await this.isPaused(config)) {
      throw new Error('Contract is paused')
    }

    const chainId = toChainId(args.recipientChain)
    const mint = await this.mintAccountAddress(config)

    const transferArgs: TransferArgs = {
      amount: args.amount,
      recipientChain: { id: chainId },
      recipientAddress: Array.from(args.recipientAddress),
      shouldQueue: args.shouldQueue
    }

    const transferIx = await this.program.methods
      .transferBurn(transferArgs)
      .accountsStrict({
        common: {
          payer: args.payer,
          config: { config: this.configAccountAddress() },
          mint,
          from: args.from,
          tokenProgram: await this.tokenProgram(config),
          outboxItem: args.outboxItem,
          outboxRateLimit: this.outboxRateLimitAccountAddress(),
          custody: await this.custodyAccountAddress(config),
          systemProgram: SystemProgram.programId,
        },
        peer: this.peerAccountAddress(args.recipientChain),
        inboxRateLimit: this.inboxRateLimitAccountAddress(args.recipientChain),
        sessionAuthority: this.sessionAuthorityAddress(args.fromAuthority, transferArgs),
        tokenAuthority: this.tokenAuthorityAddress()
      })
      .instruction()

    const mintInfo = await splToken.getMint(
      this.program.provider.connection,
      config.mint,
      undefined,
      config.tokenProgram
    )
    const transferHook = splToken.getTransferHook(mintInfo)

    if (transferHook) {
      const source = args.from
      const mint = config.mint
      const destination = await this.custodyAccountAddress(config)
      const owner = this.sessionAuthorityAddress(args.fromAuthority, transferArgs)
      await addExtraAccountMetasForExecute(
        this.program.provider.connection,
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
        0,
      );
    }

    return transferIx
  }

  /**
   * Creates a transfer_lock instruction. The `payer`, `fromAuthority`, and `outboxItem`
   * arguments must sign the transaction
   */
  async createTransferLockInstruction(args: {
    payer: PublicKey
    from: PublicKey
    fromAuthority: PublicKey
    amount: BN
    recipientChain: ChainName
    recipientAddress: ArrayLike<number>
    shouldQueue: boolean
    outboxItem: PublicKey
    config?: Config
  }): Promise<TransactionInstruction> {
    const config = await this.getConfig(args.config)

    if (await this.isPaused(config)) {
      throw new Error('Contract is paused')
    }

    const chainId = toChainId(args.recipientChain)
    const mint = await this.mintAccountAddress(config)

    const transferArgs: TransferArgs = {
      amount: args.amount,
      recipientChain: { id: chainId },
      recipientAddress: Array.from(args.recipientAddress),
      shouldQueue: args.shouldQueue
    }

    const transferIx = await this.program.methods
      .transferLock(transferArgs)
      .accounts({
        common: {
          payer: args.payer,
          config: { config: this.configAccountAddress() },
          mint,
          from: args.from,
          tokenProgram: await this.tokenProgram(config),
          outboxItem: args.outboxItem,
          outboxRateLimit: this.outboxRateLimitAccountAddress(),
          custody: await this.custodyAccountAddress(config)
        },
        peer: this.peerAccountAddress(args.recipientChain),
        inboxRateLimit: this.inboxRateLimitAccountAddress(args.recipientChain),
        sessionAuthority: this.sessionAuthorityAddress(args.fromAuthority, transferArgs)
      })
      .instruction()

    const mintInfo = await splToken.getMint(
      this.program.provider.connection,
      config.mint,
      undefined,
      config.tokenProgram
    )
    const transferHook = splToken.getTransferHook(mintInfo)

    if (transferHook) {
      const source = args.from
      const mint = config.mint
      const destination = await this.custodyAccountAddress(config)
      const owner = this.sessionAuthorityAddress(args.fromAuthority, transferArgs)
      await addExtraAccountMetasForExecute(
        this.program.provider.connection,
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
        0,
      );
    }

    return transferIx

  }

  /**
   * Creates a release_outbound instruction. The `payer` needs to sign the transaction.
   */
  async createReleaseOutboundInstruction(args: {
    payer: PublicKey
    outboxItem: PublicKey
    revertOnDelay: boolean
  }): Promise<TransactionInstruction> {
    const whAccs = getWormholeDerivedAccounts(this.program.programId, this.wormholeId)

    return await this.program.methods
      .releaseWormholeOutbound({
        revertOnDelay: args.revertOnDelay
      })
      .accounts({
        payer: args.payer,
        config: { config: this.configAccountAddress() },
        outboxItem: args.outboxItem,
        wormholeMessage: this.wormholeMessageAccountAddress(args.outboxItem),
        emitter: whAccs.wormholeEmitter,
        transceiver: this.registeredTransceiverAddress(this.program.programId),
        wormhole: {
          bridge: whAccs.wormholeBridge,
          feeCollector: whAccs.wormholeFeeCollector,
          sequence: whAccs.wormholeSequence,
          program: this.wormholeId
        }
      })
      .instruction()
  }

  async releaseOutbound(args: {
    payer: Keypair
    outboxItem: PublicKey
    revertOnDelay: boolean
    config?: Config
  }) {
    if (await this.isPaused()) {
      throw new Error('Contract is paused')
    }

    const txArgs = {
      ...args,
      payer: args.payer.publicKey
    }

    const tx = new Transaction()
    tx.add(await this.createReleaseOutboundInstruction(txArgs))

    const signers = [args.payer]
    return await this.sendAndConfirmTransaction(tx, signers)
  }

  // TODO: document that if recipient is provided, then the instruction can be
  // created before the inbox item is created (i.e. they can be put in the same tx)
  async createReleaseInboundMintInstruction(args: {
    payer: PublicKey
    chain: ChainName | ChainId
    nttMessage: NttMessage
    revertOnDelay: boolean
    recipient?: PublicKey
    config?: Config
  }): Promise<TransactionInstruction> {
    const config = await this.getConfig(args.config)

    if (await this.isPaused(config)) {
      throw new Error('Contract is paused')
    }

    const recipientAddress =
      args.recipient ?? (await this.getInboxItem(args.chain, args.nttMessage)).recipientAddress

    const mint = await this.mintAccountAddress(config)

    const transferIx = await this.program.methods
      .releaseInboundMint({
        revertOnDelay: args.revertOnDelay
      })
      .accountsStrict({
        common: {
          payer: args.payer,
          config: { config: this.configAccountAddress() },
          inboxItem: this.inboxItemAccountAddress(args.chain, args.nttMessage),
          recipient: getAssociatedTokenAddressSync(mint, recipientAddress, true, config.tokenProgram),
          mint,
          tokenAuthority: this.tokenAuthorityAddress(),
          tokenProgram: config.tokenProgram,
          custody: await this.custodyAccountAddress(config)
        }
      })
      .instruction()

    const mintInfo = await splToken.getMint(this.program.provider.connection, config.mint, undefined, config.tokenProgram)
    const transferHook = splToken.getTransferHook(mintInfo)

    if (transferHook) {
      const source = await this.custodyAccountAddress(config)
      const mint = config.mint
      const destination = getAssociatedTokenAddressSync(mint, recipientAddress, true, config.tokenProgram)
      const owner = this.tokenAuthorityAddress()
      await addExtraAccountMetasForExecute(
        this.program.provider.connection,
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
        0,
      );
    }

    return transferIx
  }

  async releaseInboundMint(args: {
    payer: Keypair
    chain: ChainName | ChainId
    nttMessage: NttMessage
    revertOnDelay: boolean
    config?: Config
  }): Promise<void> {
    if (await this.isPaused()) {
      throw new Error('Contract is paused')
    }

    const txArgs = {
      ...args,
      payer: args.payer.publicKey
    }

    const tx = new Transaction()
    tx.add(await this.createReleaseInboundMintInstruction(txArgs))

    const signers = [args.payer]
    await this.sendAndConfirmTransaction(tx, signers)
  }

  async createReleaseInboundUnlockInstruction(args: {
    payer: PublicKey
    chain: ChainName | ChainId
    nttMessage: NttMessage
    revertOnDelay: boolean
    recipient?: PublicKey
    config?: Config
  }): Promise<TransactionInstruction> {
    const config = await this.getConfig(args.config)

    if (await this.isPaused(config)) {
      throw new Error('Contract is paused')
    }

    const recipientAddress =
      args.recipient ?? (await this.getInboxItem(args.chain, args.nttMessage)).recipientAddress

    const mint = await this.mintAccountAddress(config)

    const transferIx = await this.program.methods
      .releaseInboundUnlock({
        revertOnDelay: args.revertOnDelay
      })
      .accountsStrict({
        common: {
          payer: args.payer,
          config: { config: this.configAccountAddress() },
          inboxItem: this.inboxItemAccountAddress(args.chain, args.nttMessage),
          recipient: getAssociatedTokenAddressSync(mint, recipientAddress, true, config.tokenProgram),
          mint,
          tokenAuthority: this.tokenAuthorityAddress(),
          tokenProgram: config.tokenProgram,
          custody: await this.custodyAccountAddress(config)
        },
      })
      .instruction()

    const mintInfo = await splToken.getMint(this.program.provider.connection, config.mint, undefined, config.tokenProgram)
    const transferHook = splToken.getTransferHook(mintInfo)

    if (transferHook) {
      const source = await this.custodyAccountAddress(config)
      const mint = config.mint
      const destination = getAssociatedTokenAddressSync(mint, recipientAddress, true, config.tokenProgram)
      const owner = this.tokenAuthorityAddress()
      await addExtraAccountMetasForExecute(
        this.program.provider.connection,
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
        0,
      );
    }

    return transferIx
  }

  async releaseInboundUnlock(args: {
    payer: Keypair
    chain: ChainName | ChainId
    nttMessage: NttMessage
    revertOnDelay: boolean
    config?: Config
  }): Promise<void> {
    if (await this.isPaused()) {
      throw new Error('Contract is paused')
    }

    const txArgs = {
      ...args,
      payer: args.payer.publicKey
    }

    const tx = new Transaction()
    tx.add(await this.createReleaseInboundUnlockInstruction(txArgs))

    const signers = [args.payer]
    await this.sendAndConfirmTransaction(tx, signers)
  }

  async setPeer(args: {
    payer: Keypair
    owner: Keypair
    chain: ChainName
    address: ArrayLike<number>
    limit: BN
    tokenDecimals: number
    config?: Config
  }) {
    const ix = await this.program.methods.setPeer({
      chainId: { id: toChainId(args.chain) },
      address: Array.from(args.address),
      limit: args.limit,
      tokenDecimals: args.tokenDecimals
    })
      .accounts({
        payer: args.payer.publicKey,
        owner: args.owner.publicKey,
        config: this.configAccountAddress(),
        peer: this.peerAccountAddress(args.chain),
        inboxRateLimit: this.inboxRateLimitAccountAddress(args.chain)
      }).instruction()
    return await this.sendAndConfirmTransaction(new Transaction().add(ix), [args.payer, args.owner])
  }

  async setWormholeTransceiverPeer(args: {
    payer: Keypair
    owner: Keypair
    chain: ChainName
    address: ArrayLike<number>
    config?: Config
  }) {
    const ix = await this.program.methods.setWormholePeer({
      chainId: { id: toChainId(args.chain) },
      address: Array.from(args.address)
    })
      .accounts({
        payer: args.payer.publicKey,
        owner: args.owner.publicKey,
        config: this.configAccountAddress(),
        peer: this.transceiverPeerAccountAddress(args.chain)
      }).instruction()

    const wormholeMessage = Keypair.generate()
    const whAccs = getWormholeDerivedAccounts(this.program.programId, this.wormholeId)
    const broadcastIx = await this.program.methods.broadcastWormholePeer({ chainId: toChainId(args.chain) })
      .accounts({
        payer: args.payer.publicKey,
        config: this.configAccountAddress(),
        peer: this.transceiverPeerAccountAddress(args.chain),
        wormholeMessage: wormholeMessage.publicKey,
        emitter: this.emitterAccountAddress(),
        wormhole: {
          bridge: whAccs.wormholeBridge,
          feeCollector: whAccs.wormholeFeeCollector,
          sequence: whAccs.wormholeSequence,
          program: this.wormholeId
        }
      }).instruction()
    return await this.sendAndConfirmTransaction(new Transaction().add(ix, broadcastIx), [args.payer, args.owner, wormholeMessage])
  }

  async registerTransceiver(args: {
    payer: Keypair
    owner: Keypair
    transceiver: PublicKey
  }) {
    const ix = await this.program.methods.registerTransceiver()
      .accounts({
        payer: args.payer.publicKey,
        owner: args.owner.publicKey,
        config: this.configAccountAddress(),
        transceiver: args.transceiver,
        registeredTransceiver: this.registeredTransceiverAddress(args.transceiver)
      }).instruction()

    const wormholeMessage = Keypair.generate()
    const whAccs = getWormholeDerivedAccounts(this.program.programId, this.wormholeId)
    const broadcastIx = await this.program.methods.broadcastWormholeId()
      .accounts({
        payer: args.payer.publicKey,
        config: this.configAccountAddress(),
        mint: await this.mintAccountAddress(),
        wormholeMessage: wormholeMessage.publicKey,
        emitter: this.emitterAccountAddress(),
        wormhole: {
          bridge: whAccs.wormholeBridge,
          feeCollector: whAccs.wormholeFeeCollector,
          sequence: whAccs.wormholeSequence,
          program: this.wormholeId
        }
      }).instruction()
    return await this.sendAndConfirmTransaction(
      new Transaction().add(ix, broadcastIx), [args.payer, args.owner, wormholeMessage])
  }

  async setOutboundLimit(args: {
    owner: Keypair
    chain: ChainName
    limit: BN
  }) {
    const ix = await this.program.methods.setOutboundLimit({
      limit: args.limit
    })
      .accounts({
        owner: args.owner.publicKey,
        config: this.configAccountAddress(),
        rateLimit: this.outboxRateLimitAccountAddress(),
      }).instruction();
    return this.sendAndConfirmTransaction(new Transaction().add(ix), [args.owner]);
  }

  async setInboundLimit(args: {
    owner: Keypair
    chain: ChainName
    limit: BN
  }) {
    const ix = await this.program.methods.setInboundLimit({
      chainId: { id: toChainId(args.chain) },
      limit: args.limit
    })
      .accounts({
        owner: args.owner.publicKey,
        config: this.configAccountAddress(),
        rateLimit: this.inboxRateLimitAccountAddress(args.chain),
      }).instruction();
    return this.sendAndConfirmTransaction(new Transaction().add(ix), [args.owner]);
  }

  async createReceiveWormholeMessageInstruction(args: {
    payer: PublicKey
    vaa: SignedVaa
    config?: Config
  }): Promise<TransactionInstruction> {
    const config = await this.getConfig(args.config)

    if (await this.isPaused(config)) {
      throw new Error('Contract is paused')
    }

    const wormholeNTT = deserialize('Ntt:WormholeTransfer', args.vaa)
    const nttMessage = wormholeNTT.payload.nttManagerPayload
    // NOTE: we do an 'as ChainId' cast here, which is generally unsafe.
    // TODO: explain why this is fine here
    const chainId = SDKv2toChainId(wormholeNTT.emitterChain) as ChainId

    const transceiverPeer = this.transceiverPeerAccountAddress(chainId)

    return await this.program.methods.receiveWormholeMessage().accounts({
      payer: args.payer,
      config: { config: this.configAccountAddress() },
      peer: transceiverPeer,
      vaa: derivePostedVaaKey(this.wormholeId, Buffer.from(wormholeNTT.hash)),
      transceiverMessage: this.transceiverMessageAccountAddress(
        chainId,
        nttMessage.id
      )
    }).instruction()
  }

  async createRedeemInstruction(args: {
    payer: PublicKey
    vaa: SignedVaa
    config?: Config
  }): Promise<TransactionInstruction> {
    const config = await this.getConfig(args.config)

    if (await this.isPaused(config)) {
      throw new Error('Contract is paused')
    }

    const wormholeNTT = deserialize('Ntt:WormholeTransfer', args.vaa)
    const nttMessage = wormholeNTT.payload.nttManagerPayload
    // NOTE: we do an 'as ChainId' cast here, which is generally unsafe.
    // TODO: explain why this is fine here
    const chainId = SDKv2toChainId(wormholeNTT.emitterChain) as ChainId

    const nttManagerPeer = this.peerAccountAddress(chainId)
    const inboxRateLimit = this.inboxRateLimitAccountAddress(chainId)

    return await this.program.methods
      .redeem({})
      .accounts({
        payer: args.payer,
        config: this.configAccountAddress(),
        peer: nttManagerPeer,
        transceiverMessage: this.transceiverMessageAccountAddress(chainId, nttMessage.id),
        transceiver: this.registeredTransceiverAddress(this.program.programId),
        mint: await this.mintAccountAddress(config),
        inboxItem: this.inboxItemAccountAddress(chainId, nttMessage),
        inboxRateLimit,
        outboxRateLimit: this.outboxRateLimitAccountAddress()
      })
      .instruction()
  }

  /**
   * Redeems a VAA.
   *
   * @returns Whether the transfer was released. If the transfer was delayed,
   *          this will be false. In that case, a subsequent call to
   *          `releaseInboundMint` or `releaseInboundUnlock` will release the
   *          transfer after the delay (24h).
   */
  async redeem(args: {
    payer: Keypair
    vaa: SignedVaa
    config?: Config
  }): Promise<boolean> {
    const config = await this.getConfig(args.config)

    const redeemArgs = {
      ...args,
      payer: args.payer.publicKey
    }

    const wormholeNTT = deserialize('Ntt:WormholeTransfer', args.vaa)
    const nttMessage = wormholeNTT.payload.nttManagerPayload
    // TODO: explain why this is fine here
    const chainId = SDKv2toChainId(wormholeNTT.emitterChain) as ChainId

    // Here we create a transaction with three instructions:
    // 1. receive wormhole messsage (vaa)
    // 1. redeem
    // 2. releaseInboundMint or releaseInboundUnlock (depending on mode)
    //
    // The first instruction verifies the VAA.
    // The second instruction places the transfer in the inbox, then the third instruction
    // releases it.
    //
    // In case the redeemed amount exceeds the remaining inbound rate limit capacity,
    // the transaction gets delayed. If this happens, the second instruction will not actually
    // be able to release the transfer yet.
    // To make sure the transaction still succeeds, we set revertOnDelay to false, which will
    // just make the second instruction a no-op in case the transfer is delayed.

    const tx = new Transaction()
    tx.add(await this.createReceiveWormholeMessageInstruction(redeemArgs))
    tx.add(await this.createRedeemInstruction(redeemArgs))

    const releaseArgs = {
      ...args,
      payer: args.payer.publicKey,
      nttMessage,
      recipient: new PublicKey(nttMessage.payload.recipientAddress.toUint8Array()),
      chain: chainId,
      revertOnDelay: false,
      config: config
    }

    if (config.mode.locking != null) {
      tx.add(await this.createReleaseInboundUnlockInstruction(releaseArgs))
    } else {
      tx.add(await this.createReleaseInboundMintInstruction(releaseArgs))
    }

    const signers = [args.payer]
    await this.sendAndConfirmTransaction(tx, signers)

    // Let's check if the transfer was released
    const inboxItem = await this.getInboxItem(chainId, nttMessage)
    return inboxItem.releaseStatus.released !== undefined
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
  async getConfig(config?: Config): Promise<Config> {
    return config ?? await this.program.account.config.fetch(this.configAccountAddress())
  }

  async isPaused(config?: Config): Promise<boolean> {
    return (await this.getConfig(config)).paused
  }

  async mintAccountAddress(config?: Config): Promise<PublicKey> {
    return (await this.getConfig(config)).mint
  }

  async tokenProgram(config?: Config): Promise<PublicKey> {
    return (await this.getConfig(config)).tokenProgram
  }

  async getInboxItem(chain: ChainName | ChainId, nttMessage: NttMessage): Promise<InboxItem> {
    return await this.program.account.inboxItem.fetch(this.inboxItemAccountAddress(chain, nttMessage))
  }

  async getAddressLookupTable(useCache = true): Promise<AddressLookupTableAccount> {
    if (!useCache || !this.addressLookupTable) {
      const lut = await this.program.account.lut.fetchNullable(this.lutAccountAddress())
      if (!lut) {
        throw new Error('Address lookup table not found. Did you forget to call initializeLUT?')
      }
      const response = await this.program.provider.connection.getAddressLookupTable(lut.address)
      this.addressLookupTable = response.value
    }
    if (!this.addressLookupTable) {
      throw new Error('Address lookup table not found. Did you forget to call initializeLUT?')
    }
    return this.addressLookupTable
  }

  /**
   * Returns the address of the custody account. If the config is available
   * (i.e. the program is initialised), the mint is derived from the config.
   * Otherwise, the mint must be provided.
   */
  async custodyAccountAddress(configOrMint: Config | PublicKey, tokenProgram = splToken.TOKEN_PROGRAM_ID): Promise<PublicKey> {
    if (configOrMint instanceof PublicKey) {
      return splToken.getAssociatedTokenAddress(configOrMint, this.tokenAuthorityAddress(), true, tokenProgram)
    } else {
      return splToken.getAssociatedTokenAddress(configOrMint.mint, this.tokenAuthorityAddress(), true, configOrMint.tokenProgram)
    }
  }
}

function exhaustive<A>(_: never): A {
  throw new Error('Impossible')
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
    const validateStatePubkey = splToken.getExtraAccountMetaAddress(mint, programId);
    const validateStateAccount = await connection.getAccountInfo(validateStatePubkey, commitment);
    if (validateStateAccount == null) {
        return instruction;
    }
    const validateStateData = splToken.getExtraAccountMetas(validateStateAccount);

    // Check to make sure the provided keys are in the instruction
    if (![source, mint, destination, owner].every((key) => instruction.keys.some((meta) => meta.pubkey.equals(key)))) {
        throw new Error('Missing required account in instruction');
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
    instruction.keys.push({ pubkey: programId, isSigner: false, isWritable: false });
    instruction.keys.push({ pubkey: validateStatePubkey, isSigner: false, isWritable: false });
}

// TODO: delete (see above)
function deEscalateAccountMeta(accountMeta: AccountMeta, accountMetas: AccountMeta[]): AccountMeta {
    const maybeHighestPrivileges = accountMetas
        .filter((x) => x.pubkey.equals(accountMeta.pubkey))
        .reduce<{ isSigner: boolean; isWritable: boolean } | undefined>((acc, x) => {
            if (!acc) return { isSigner: x.isSigner, isWritable: x.isWritable };
            return { isSigner: acc.isSigner || x.isSigner, isWritable: acc.isWritable || x.isWritable };
        }, undefined);
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

import * as anchor from "@coral-xyz/anchor";
import * as spl from "@solana/spl-token";
import {
  PublicKey,
  SystemProgram,
  Transaction,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import {
  AccountAddress,
  ChainAddress,
  ChainContext,
  Signer,
  UniversalAddress,
  Wormhole,
  contracts,
  deserialize,
  deserializePayload,
  encoding,
  serialize,
  serializePayload,
} from "@wormhole-foundation/sdk";
import * as testing from "@wormhole-foundation/sdk-definitions/testing";
import {
  SolanaAddress,
  SolanaPlatform,
  getSolanaSignAndSendSigner,
} from "@wormhole-foundation/sdk-solana";
import { SolanaWormholeCore } from "@wormhole-foundation/sdk-solana-core";
import * as fs from "fs";
import { DummyTransferHook } from "../ts/idl/1_0_0/ts/dummy_transfer_hook.js";
import { SolanaNtt } from "../ts/sdk/index.js";
import { handleTestSkip, signSendWait } from "./utils/index.js";

handleTestSkip(__filename);

const solanaRootDir = `${__dirname}/../`;

const GUARDIAN_KEY =
  "cfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0";
const CORE_BRIDGE_ADDRESS = contracts.coreBridge("Mainnet", "Solana");
const NTT_ADDRESS = anchor.workspace.ExampleNativeTokenTransfers.programId;

const w = new Wormhole("Devnet", [SolanaPlatform], {
  chains: { Solana: { contracts: { coreBridge: CORE_BRIDGE_ADDRESS } } },
});

const remoteXcvr: ChainAddress = {
  chain: "Ethereum",
  address: new UniversalAddress(
    encoding.bytes.encode("transceiver".padStart(32, "\0"))
  ),
};
const remoteMgr: ChainAddress = {
  chain: "Ethereum",
  address: new UniversalAddress(
    encoding.bytes.encode("nttManager".padStart(32, "\0"))
  ),
};

const payerSecretKey = Uint8Array.from(
  JSON.parse(
    fs.readFileSync(`${solanaRootDir}/keys/test.json`, {
      encoding: "utf-8",
    })
  )
);
const payer = anchor.web3.Keypair.fromSecretKey(payerSecretKey);

const connection = new anchor.web3.Connection(
  "http://localhost:8899",
  "confirmed"
);

// make sure we're using the exact same Connection obj for rpc
const ctx: ChainContext<"Devnet", "Solana"> = w
  .getPlatform("Solana")
  .getChain("Solana", connection);

let tokenAccount: anchor.web3.PublicKey;

const mintAuthority = anchor.web3.Keypair.generate();
const mint = anchor.web3.Keypair.generate();

const dummyTransferHook = anchor.workspace
  .DummyTransferHook as anchor.Program<DummyTransferHook>;

const [extraAccountMetaListPDA] = PublicKey.findProgramAddressSync(
  [Buffer.from("extra-account-metas"), mint.publicKey.toBuffer()],
  dummyTransferHook.programId
);

const [counterPDA] = PublicKey.findProgramAddressSync(
  [Buffer.from("counter")],
  dummyTransferHook.programId
);

async function counterValue(): Promise<anchor.BN> {
  const counter = await dummyTransferHook.account.counter.fetch(counterPDA);
  return counter.count;
}

const coreBridge = new SolanaWormholeCore("Devnet", "Solana", connection, {
  coreBridge: CORE_BRIDGE_ADDRESS,
});

const TOKEN_PROGRAM = spl.TOKEN_2022_PROGRAM_ID;

describe("example-native-token-transfers", () => {
  let ntt: SolanaNtt<"Devnet", "Solana">;
  let signer: Signer;
  let sender: AccountAddress<"Solana">;
  let tokenAddress: string;

  beforeAll(async () => {
    try {
      signer = await getSolanaSignAndSendSigner(connection, payer, {
        //debug: true,
      });
      sender = Wormhole.parseAddress("Solana", signer.address());

      const extensions = [spl.ExtensionType.TransferHook];
      const mintLen = spl.getMintLen(extensions);
      const lamports = await connection.getMinimumBalanceForRentExemption(
        mintLen
      );
      const transaction = new Transaction().add(
        SystemProgram.createAccount({
          fromPubkey: payer.publicKey,
          newAccountPubkey: mint.publicKey,
          space: mintLen,
          lamports,
          programId: TOKEN_PROGRAM,
        }),
        spl.createInitializeTransferHookInstruction(
          mint.publicKey,
          mintAuthority.publicKey,
          dummyTransferHook.programId,
          TOKEN_PROGRAM
        ),
        spl.createInitializeMintInstruction(
          mint.publicKey,
          9,
          mintAuthority.publicKey,
          null,
          TOKEN_PROGRAM
        )
      );
      const { blockhash } = await connection.getLatestBlockhash();
      transaction.feePayer = payer.publicKey;
      transaction.recentBlockhash = blockhash;
      await sendAndConfirmTransaction(connection, transaction, [payer, mint], {
        commitment: "confirmed",
      });

      tokenAccount = await spl.createAssociatedTokenAccount(
        connection,
        payer,
        mint.publicKey,
        payer.publicKey,
        undefined,
        TOKEN_PROGRAM,
        spl.ASSOCIATED_TOKEN_PROGRAM_ID
      );

      await spl.mintTo(
        connection,
        payer,
        mint.publicKey,
        tokenAccount,
        mintAuthority,
        10_000_000n,
        undefined,
        undefined,
        TOKEN_PROGRAM
      );

      // create our contract client
      tokenAddress = mint.publicKey.toBase58();
      ntt = new SolanaNtt("Devnet", "Solana", connection, {
        ...ctx.config.contracts,
        ntt: {
          token: tokenAddress,
          manager: NTT_ADDRESS,
          transceiver: { wormhole: NTT_ADDRESS },
        },
      });
    } catch (e) {
      console.error("Failed to setup solana token: ", e);
      throw e;
    }
  });

  describe("Locking", () => {
    beforeAll(async () => {
      try {
        // transfer mint authority to ntt
        await spl.setAuthority(
          connection,
          payer,
          mint.publicKey,
          mintAuthority,
          spl.AuthorityType.MintTokens,
          ntt.pdas.tokenAuthority(),
          [],
          undefined,
          TOKEN_PROGRAM
        );

        // init
        const initTxs = ntt.initialize(sender, {
          mint: mint.publicKey,
          outboundLimit: 1000000n,
          mode: "locking",
        });
        await signSendWait(ctx, initTxs, signer);

        // register
        const registerTxs = ntt.registerTransceiver({
          payer,
          owner: payer,
          transceiver: ntt.program.programId,
        });
        await signSendWait(ctx, registerTxs, signer);

        // set Wormhole xcvr peer
        const setXcvrPeerTxs = ntt.setWormholeTransceiverPeer(
          remoteXcvr,
          sender
        );
        await signSendWait(ctx, setXcvrPeerTxs, signer);

        // set manager peer
        const setPeerTxs = ntt.setPeer(remoteMgr, 18, 1000000n, sender);
        await signSendWait(ctx, setPeerTxs, signer);
      } catch (e) {
        console.error("Failed to setup peer: ", e);
        throw e;
      }
    });

    it("Create ExtraAccountMetaList Account", async () => {
      const initializeExtraAccountMetaListInstruction =
        await dummyTransferHook.methods
          .initializeExtraAccountMetaList()
          .accountsStrict({
            payer: payer.publicKey,
            mint: mint.publicKey,
            counter: counterPDA,
            extraAccountMetaList: extraAccountMetaListPDA,
            tokenProgram: TOKEN_PROGRAM,
            associatedTokenProgram: spl.ASSOCIATED_TOKEN_PROGRAM_ID,
            systemProgram: SystemProgram.programId,
          })
          .instruction();

      const transaction = new Transaction().add(
        initializeExtraAccountMetaListInstruction
      );
      const { blockhash } = await connection.getLatestBlockhash();
      transaction.feePayer = payer.publicKey;
      transaction.recentBlockhash = blockhash;
      transaction.sign(payer);
      await sendAndConfirmTransaction(connection, transaction, [payer], {
        commitment: "confirmed",
      });
    });

    test("Can send tokens", async () => {
      const amount = 100000n;
      const sender = Wormhole.parseAddress("Solana", signer.address());

      const receiver = testing.utils.makeUniversalChainAddress("Ethereum");

      // TODO: keep or remove the `outboxItem` param?
      // added as a way to keep tests the same but it technically breaks the Ntt interface
      const outboxItem = anchor.web3.Keypair.generate();
      const xferTxs = ntt.transfer(
        sender,
        amount,
        receiver,
        { queue: false, automatic: false, gasDropoff: 0n },
        outboxItem
      );
      await signSendWait(ctx, xferTxs, signer);

      const wormholeMessage = ntt.pdas.wormholeMessageAccount(
        outboxItem.publicKey
      );

      const unsignedVaa = await coreBridge.parsePostMessageAccount(
        wormholeMessage
      );

      const transceiverMessage = deserializePayload(
        "Ntt:WormholeTransfer",
        unsignedVaa.payload
      );

      // assert that amount is what we expect
      expect(
        transceiverMessage.nttManagerPayload.payload.trimmedAmount
      ).toMatchObject({ amount: 10000n, decimals: 8 });

      // get from balance
      const balance = await connection.getTokenAccountBalance(tokenAccount);
      expect(balance.value.amount).toBe("9900000");
    });

    it("Can receive tokens", async () => {
      const emitter = new testing.mocks.MockEmitter(
        remoteXcvr.address as UniversalAddress,
        "Ethereum",
        0n
      );

      const guardians = new testing.mocks.MockGuardians(0, [GUARDIAN_KEY]);
      const sender = Wormhole.parseAddress("Solana", signer.address());

      const sendingTransceiverMessage = {
        sourceNttManager: remoteMgr.address as UniversalAddress,
        recipientNttManager: new UniversalAddress(
          ntt.program.programId.toBytes()
        ),
        nttManagerPayload: {
          id: encoding.bytes.encode("sequence1".padEnd(32, "0")),
          sender: new UniversalAddress("FACE".padStart(64, "0")),
          payload: {
            trimmedAmount: {
              amount: 10000n,
              decimals: 8,
            },
            sourceToken: new UniversalAddress("FAFA".padStart(64, "0")),
            recipientAddress: new UniversalAddress(payer.publicKey.toBytes()),
            recipientChain: "Solana",
          },
        },
        transceiverPayload: new Uint8Array(),
      } as const;

      const serialized = serializePayload(
        "Ntt:WormholeTransfer",
        sendingTransceiverMessage
      );
      const published = emitter.publishMessage(0, serialized, 200);
      const rawVaa = guardians.addSignatures(published, [0]);
      const vaa = deserialize("Ntt:WormholeTransfer", serialize(rawVaa));

      const redeemTxs = ntt.redeem([vaa], sender);
      try {
        await signSendWait(ctx, redeemTxs, signer);
      } catch (e) {
        console.error(e);
        throw e;
      }

      expect((await counterValue()).toString()).toEqual("2");
    });
  });

  describe("Static Checks", () => {
    const wh = new Wormhole("Devnet", [SolanaPlatform]);
    const ctx = wh.getChain("Solana");
    const overrides = {
      Solana: {
        token: tokenAddress,
        manager: NTT_ADDRESS,
        transceiver: { wormhole: NTT_ADDRESS },
      },
    };

    describe("ABI Versions Test", function () {
      test("It initializes from Rpc", async function () {
        const ntt = await SolanaNtt.fromRpc(connection, {
          Solana: {
            ...ctx.config,
            contracts: {
              ...ctx.config.contracts,
              ntt: overrides["Solana"],
            },
          },
        });
        expect(ntt).toBeTruthy();
      });

      test("It initializes from constructor", async function () {
        const ntt = new SolanaNtt("Devnet", "Solana", connection, {
          ...ctx.config.contracts,
          ...{ ntt: overrides["Solana"] },
        });
        expect(ntt).toBeTruthy();
      });

      test("It gets the correct version", async function () {
        const version = await SolanaNtt.getVersion(
          connection,
          { ntt: overrides["Solana"] },
          new SolanaAddress(payer.publicKey.toBase58())
        );
        expect(version).toBe("2.0.0");
      });
    });
  });
});

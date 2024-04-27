import * as anchor from "@coral-xyz/anchor";
import { BN } from "@coral-xyz/anchor";
import * as spl from "@solana/spl-token";
import * as fs from "fs";

import { encoding } from "@wormhole-foundation/sdk-base";
import {
  UniversalAddress,
  deserializePayload,
  serializePayload,
} from "@wormhole-foundation/sdk-definitions";
import { NTT, postVaa } from "../ts/lib/index.js";

import {
  PublicKey,
  SystemProgram,
  Transaction,
  sendAndConfirmTransaction,
} from "@solana/web3.js";

import { serialize, testing } from "@wormhole-foundation/sdk-connect";
import { deserializePostMessage } from "@wormhole-foundation/sdk-solana-core";
import { DummyTransferHook } from "../target/types/dummy_transfer_hook.js";

export const GUARDIAN_KEY =
  "cfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0";

describe("example-native-token-transfers", () => {
  const payerSecretKey = Uint8Array.from(
    JSON.parse(
      fs.readFileSync(`${__dirname}/../keys/test.json`, { encoding: "utf-8" })
    )
  );
  const payer = anchor.web3.Keypair.fromSecretKey(payerSecretKey);

  const owner = anchor.web3.Keypair.generate();
  const connection = new anchor.web3.Connection(
    "http://localhost:8899",
    "confirmed"
  );
  const ntt = new NTT(connection, {
    nttId: "nttiK1SepaQt6sZ4WGW5whvc9tEnGXGxuKeptcQPCcS",
    wormholeId: "worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth",
  });
  const user = anchor.web3.Keypair.generate();
  let tokenAccount: anchor.web3.PublicKey;

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

  it("Initialize mint", async () => {
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
        programId: spl.TOKEN_2022_PROGRAM_ID,
      }),
      spl.createInitializeTransferHookInstruction(
        mint.publicKey,
        owner.publicKey,
        dummyTransferHook.programId,
        spl.TOKEN_2022_PROGRAM_ID
      ),
      spl.createInitializeMintInstruction(
        mint.publicKey,
        9,
        owner.publicKey,
        null,
        spl.TOKEN_2022_PROGRAM_ID
      )
    );

    await sendAndConfirmTransaction(connection, transaction, [payer, mint]);

    tokenAccount = await spl.createAssociatedTokenAccount(
      connection,
      payer,
      mint.publicKey,
      user.publicKey,
      undefined,
      spl.TOKEN_2022_PROGRAM_ID,
      spl.ASSOCIATED_TOKEN_PROGRAM_ID
    );

    await spl.mintTo(
      connection,
      payer,
      mint.publicKey,
      tokenAccount,
      owner,
      BigInt(10000000),
      undefined,
      undefined,
      spl.TOKEN_2022_PROGRAM_ID
    );
  });

  it("Can check version", async () => {
    const version = await ntt.version(payer.publicKey);
    expect(version).toEqual("1.0.0");
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
          tokenProgram: spl.TOKEN_2022_PROGRAM_ID,
          associatedTokenProgram: spl.ASSOCIATED_TOKEN_PROGRAM_ID,
          systemProgram: SystemProgram.programId,
        })
        .instruction();

    const transaction = new Transaction().add(
      initializeExtraAccountMetaListInstruction
    );

    await sendAndConfirmTransaction(connection, transaction, [payer]);
  });

  describe("Burning", () => {
    beforeAll(async () => {
      await spl.setAuthority(
        connection,
        payer,
        mint.publicKey,
        owner,
        spl.AuthorityType.MintTokens,
        ntt.pdas.tokenAuthority(),
        [],
        undefined,
        spl.TOKEN_2022_PROGRAM_ID
      );

      await ntt.initialize({
        payer,
        owner: payer,
        chain: "Solana",
        mint: mint.publicKey,
        outboundLimit: new BN(1000000),
        mode: "burning",
      });

      // NOTE: this is a hack. The next instruction will fail if we don't wait
      // here, because the address lookup table is not yet available, despite
      // the transaction having been confirmed.
      // Looks like a bug, but I haven't investigated further. In practice, this
      // won't be an issue, becase the address lookup table will have been
      // created well before anyone is trying to use it, but we might want to be
      // mindful in the deploy script too.
      await new Promise((resolve) => setTimeout(resolve, 200));

      await ntt.registerTransceiver({
        payer,
        owner: payer,
        transceiver: ntt.program.programId,
      });

      await ntt.setWormholeTransceiverPeer({
        payer,
        owner: payer,
        chain: "Ethereum",
        address: Buffer.from("transceiver".padStart(32, "\0")),
      });

      await ntt.setPeer({
        payer,
        owner: payer,
        chain: "Ethereum",
        address: Buffer.from("nttManager".padStart(32, "\0")),
        limit: new BN(1000000),
        tokenDecimals: 18,
      });
    });

    it("Can send tokens", async () => {
      // TODO: factor out this test so it can be reused for burn&mint

      // transfer some tokens

      const amount = new BN(100000);

      const outboxItem = await ntt.transfer({
        payer,
        from: tokenAccount,
        fromAuthority: user,
        amount,
        recipientChain: "Ethereum",
        recipientAddress: Array.from(user.publicKey.toBuffer()), // TODO: dummy
        shouldQueue: false,
      });

      const wormholeMessage = ntt.pdas.wormholeMessageAccount(outboxItem);

      const wormholeMessageAccount = await connection.getAccountInfo(
        wormholeMessage
      );
      if (wormholeMessageAccount === null) {
        throw new Error("wormhole message account not found");
      }

      const messageData = deserializePostMessage(wormholeMessageAccount.data);
      const transceiverMessage = deserializePayload(
        "Ntt:WormholeTransfer",
        messageData.payload
      );

      // assert theat amount is what we expect
      expect(
        transceiverMessage.nttManagerPayload.payload.trimmedAmount
      ).toEqual({ amount: 10000n, decimals: 8 });
      // get from balance
      const balance = await connection.getTokenAccountBalance(tokenAccount);
      expect(balance.value.amount).toEqual("9900000");

      expect((await counterValue()).toString()).toEqual("1");
    });

    it("Can receive tokens", async () => {
      const emitter = new testing.mocks.MockEmitter(
        new UniversalAddress(
          encoding.bytes.zpad(encoding.bytes.encode("transceiver"), 32)
        ),
        "Ethereum"
      );

      const guardians = new testing.mocks.MockGuardians(0, [GUARDIAN_KEY]);

      const sendingTransceiverMessage = {
        sourceNttManager: new UniversalAddress(
          encoding.bytes.encode("nttManager".padStart(32, "\0"))
        ),
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
            recipientAddress: new UniversalAddress(user.publicKey.toBytes()),
            recipientChain: "Solana",
          },
        },
        transceiverPayload: new Uint8Array(),
      } as const;

      const serialized = serializePayload(
        "Ntt:WormholeTransfer",
        sendingTransceiverMessage
      );

      const published = emitter.publishMessage(0, serialized, 0);

      const vaa = guardians.addSignatures(published, [0]);

      const txids = await postVaa(connection, payer, vaa, ntt.wormholeId);
      console.log("Posted VAA", txids);

      const released = await ntt.redeem({ payer, vaa: serialize(vaa) });

      expect(released).toEqual(true);

      expect((await counterValue()).toString()).toEqual("2");
    });
  });
});

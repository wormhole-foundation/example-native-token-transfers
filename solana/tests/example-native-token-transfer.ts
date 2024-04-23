import * as anchor from "@coral-xyz/anchor";
import { BN } from "@coral-xyz/anchor";
import * as spl from "@solana/spl-token";
import { PostedMessageData, derivePostedVaaKey } from "@certusone/wormhole-sdk/lib/cjs/solana/wormhole";
import { expect } from "chai";
import { ParsedVaa, parseVaa, toChainId } from "@certusone/wormhole-sdk";
import {
  MockEmitter,
  MockGuardians,
} from "@certusone/wormhole-sdk/lib/cjs/mock";
import * as fs from "fs";

import { encoding } from "@wormhole-foundation/sdk-base";
import {
  UniversalAddress,
  serializePayload,
  deserializePayload,
} from "@wormhole-foundation/sdk-definitions";
import { postVaa, NTT, nttMessageLayout } from "../ts/sdk";
import {
  WormholeTransceiverMessage,
} from "../ts/sdk/nttLayout";
import { appendGovernanceHeader, derivePda, deserializeInstruction, serializeInstruction, verifyGovernanceHeader } from "../ts/sdk/utils";

import { type WormholeGovernance } from '../target/types/wormhole_governance';
import IDL from '../target/idl/wormhole_governance.json';
import { Connection } from "@solana/web3.js";

// TODO: move this elsewhere
export class Governance {
  program: anchor.Program<WormholeGovernance>;

  constructor(connection: Connection, args: { governanceProgramId: string }) {
    this.program = new anchor.Program(IDL as any as WormholeGovernance, args.governanceProgramId);
  }
}

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

  let mint: anchor.web3.PublicKey;

  before(async () => {
    // airdrop some tokens to payer
    mint = await spl.createMint(connection, payer, owner.publicKey, null, 9);

    tokenAccount = await spl.createAssociatedTokenAccount(
      connection,
      payer,
      mint,
      user.publicKey
    );
    await spl.mintTo(
      connection,
      payer,
      mint,
      tokenAccount,
      owner,
      BigInt(10000000)
    );
  });

  it("Can check version", async () => {
    const version = await ntt.version(payer.publicKey);
    expect(version).to.equal("1.0.0");
  });

  describe("Locking", () => {
    before(async () => {
      await spl.setAuthority(
        connection,
        payer,
        mint,
        owner,
        0, // mint
        ntt.tokenAuthorityAddress()
      );

      await ntt.initialize({
        payer,
        owner: payer,
        chain: "solana",
        mint,
        outboundLimit: new BN(1000000),
        mode: "locking",
      });

      await ntt.registerTransceiver({
        payer,
        owner: payer,
        transceiver: ntt.program.programId,
      });

      await ntt.setWormholeTransceiverPeer({
        payer,
        owner: payer,
        chain: "ethereum",
        address: Buffer.from("transceiver".padStart(32, "\0")),
      });

      await ntt.setPeer({
        payer,
        owner: payer,
        chain: "ethereum",
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
        recipientChain: "ethereum",
        recipientAddress: Array.from(user.publicKey.toBuffer()), // TODO: dummy
        shouldQueue: false,
      });

      const wormholeMessage = ntt.wormholeMessageAccountAddress(outboxItem);

      const wormholeMessageAccount = await connection.getAccountInfo(
        wormholeMessage
      );
      if (wormholeMessageAccount === null) {
        throw new Error("wormhole message account not found");
      }

      const messageData = PostedMessageData.deserialize(
        wormholeMessageAccount.data
      );
      const transceiverMessage = deserializePayload(
        "Ntt:WormholeTransfer",
        messageData.message.payload
      );

      // assert theat amount is what we expect
      expect(
        transceiverMessage.nttManagerPayload.payload.trimmedAmount
      ).to.deep.equal({ amount: 10000n, decimals: 8 });
      // get from balance
      const balance = await connection.getTokenAccountBalance(tokenAccount);
      expect(balance.value.amount).to.equal("9900000");

      // grab logs
      // await connection.confirmTransaction(redeemTx, 'confirmed');
      // const tx = await anchor.getProvider().connection.getParsedTransaction(redeemTx, {
      //   commitment: "confirmed",
      // });
      // console.log(tx);

      // const log = tx.meta.logMessages[1];
      // const message = log.substring(log.indexOf(':') + 1);
      // console.log(message);

      // TODO: assert other stuff in the message
      // console.log(nttManagerMessage);
    });

    it("Can receive tokens", async () => {
      const emitter = new MockEmitter(
        Buffer.from("transceiver".padStart(32, "\0")).toString("hex"),
        toChainId("ethereum"),
        Number(0) // sequence
      );

      const guardians = new MockGuardians(0, [GUARDIAN_KEY]);

      const sendingTransceiverMessage: WormholeTransceiverMessage<
        typeof nttMessageLayout
      > = {
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
        transceiverPayload: { forSpecializedRelayer: false },
      } as const;

      const serialized = serializePayload(
        "Ntt:WormholeTransfer",
        sendingTransceiverMessage
      );

      const published = emitter.publishMessage(
        0, // nonce
        Buffer.from(serialized),
        0 // consistency level
      );

      const vaaBuf = guardians.addSignatures(published, [0]);

      await postVaa(connection, payer, vaaBuf, ntt.wormholeId);

      const released = await ntt.redeem({
        payer,
        vaa: vaaBuf,
      });

      expect(released).to.equal(true);
    });
  });

  describe("Admin", async () => {
    const governance = new Governance(connection, {
      governanceProgramId: 'wgvEiKVzX9yyEoh41jZAdC6JqGUTS4CFXbFGBV5TKdZ'
    });

    const emitter = new MockEmitter(
      "0000000000000000000000000000000000000000000000000000000000000004", // TODO: constant
      toChainId("solana"),
      Number(0) // sequence
    );

    const guardians = new MockGuardians(0, [GUARDIAN_KEY]);

    it("Can transfer ownership to governance program", async () => {
      await ntt.transferOwnership({
        payer: payer,
        owner: payer,
        newOwner: derivePda('governance', governance.program.programId)
      })
    })

    it("Original owner can reclaim ownership", async () => {
      await ntt.claimOwnership({
        payer: payer,
        owner: payer,
      })
      await ntt.transferOwnership({
        payer: payer,
        owner: payer,
        newOwner: derivePda('governance', governance.program.programId)
      })
    })

    it("Governance program can claim ownership", async () => {
      const OWNER = new anchor.web3.PublicKey(Buffer.from("owner".padEnd(32, "\0")))
      const ix = await ntt.createClaimOwnershipInstruction({
        newOwner: OWNER
      })
      // verified works
      const serializedIx = serializeInstruction(ix)
      const governanceMessage = appendGovernanceHeader(serializedIx, governance.program.programId)

      const published = emitter.publishMessage(
        0, // nonce
        Buffer.from(governanceMessage),
        0 // consistency level
      );

      const vaaBuf = guardians.addSignatures(published, [0]);

      await postVaa(connection, payer, vaaBuf, ntt.wormholeId);

      const parsedVaa = parseVaa(vaaBuf)

      const governanceIx = await wrapGovernance(ntt.wormholeId, governance, parsedVaa, payer);

      const tx = new anchor.web3.Transaction().add(governanceIx)
      await anchor.web3.sendAndConfirmTransaction(connection, tx, [payer])
    })
  })
});

// TODO: move somewhere else
async function wrapGovernance(
  wormholeId: anchor.web3.PublicKey,
  governance: Governance,
  parsedVaa: ParsedVaa,
  payer: anchor.web3.Keypair,
) {
  const vaaKey = derivePostedVaaKey(wormholeId, parsedVaa.hash);
  const emitterChain = Buffer.alloc(2);
  emitterChain.writeUInt16BE(parsedVaa.emitterChain);
  const sequence = Buffer.alloc(8);
  sequence.writeBigUInt64BE(BigInt(parsedVaa.sequence));
  const [governanceProgramId, ixData] = verifyGovernanceHeader(parsedVaa.payload);
  const ix = deserializeInstruction(ixData);

  const governanceIx = await governance.program.methods.governance()
    .accountsStrict({
      payer: payer.publicKey,
      governance: derivePda('governance', governance.program.programId),
      vaa: vaaKey,
      program: ix.programId,
      replay: derivePda(['replay', emitterChain, parsedVaa.emitterAddress, sequence], governance.program.programId),
      systemProgram: anchor.web3.SystemProgram.programId,
    }).instruction();

  // add extra instructions
  governanceIx.keys = governanceIx.keys.concat(ix.keys.map(k => { return { ...k, isSigner: false }; }));
  return governanceIx;
}

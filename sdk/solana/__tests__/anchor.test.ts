import * as anchor from "@coral-xyz/anchor";
import * as spl from "@solana/spl-token";
import {
  ChainAddress,
  ChainContext,
  Signer,
  UniversalAddress,
  VAA,
  Wormhole,
  deserialize,
  deserializePayload,
  encoding,
  serialize,
  serializePayload,
  signSendWait as ssw,
  testing,
} from "@wormhole-foundation/sdk-connect";
import {
  SolanaAddress,
  SolanaPlatform,
  SolanaSendSigner,
} from "@wormhole-foundation/sdk-solana";
import { SolanaWormholeCore } from "@wormhole-foundation/sdk-solana-core";
import * as fs from "fs";

import { SolanaNtt } from "../src/index.js";

const solanaRootDir = `${__dirname}/../../../solana`;

const GUARDIAN_KEY =
  "cfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0";

// TODO: are these in either the SDK or anchor.toml?
const CORE_BRIDGE_ADDRESS = "worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth";
const NTT_ADDRESS = "nttiK1SepaQt6sZ4WGW5whvc9tEnGXGxuKeptcQPCcS";

async function signSendWait(
  chain: ChainContext<any, any, any>,
  txs: AsyncGenerator<any>,
  signer: Signer
) {
  try {
    await ssw(chain, txs, signer);
  } catch (e) {
    console.error(e);
  }
}

const w = new Wormhole("Devnet", [SolanaPlatform], {
  chains: {
    Solana: {
      contracts: {
        coreBridge: CORE_BRIDGE_ADDRESS,
      },
    },
  },
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

describe("example-native-token-transfers", () => {
  const payerSecretKey = Uint8Array.from(
    JSON.parse(
      fs.readFileSync(`${solanaRootDir}/keys/test.json`, {
        encoding: "utf-8",
      })
    )
  );
  const payer = anchor.web3.Keypair.fromSecretKey(payerSecretKey);
  const owner = anchor.web3.Keypair.generate();

  const connection = new anchor.web3.Connection(
    "http://localhost:8899",
    "confirmed"
  );

  // Make sure we're using the exact same Connection obj for rpc
  const ctx: ChainContext<"Devnet", "Solana"> = w
    .getPlatform("Solana")
    .getChain("Solana", connection);

  const signer = new SolanaSendSigner(connection, "Solana", payer);
  const sender = Wormhole.parseAddress(signer.chain(), signer.address());

  const coreBridge = new SolanaWormholeCore("Devnet", "Solana", connection, {
    coreBridge: CORE_BRIDGE_ADDRESS,
  });

  let tokenAccount: anchor.web3.PublicKey;
  let mint: anchor.web3.PublicKey;
  let ntt: SolanaNtt<"Devnet", "Solana">;

  beforeAll(async () => {
    // airdrop some tokens to payer
    mint = await spl.createMint(connection, payer, owner.publicKey, null, 9);

    // Create our contract client
    ntt = new SolanaNtt("Devnet", "Solana", connection, {
      ...ctx.config.contracts,
      ntt: {
        token: mint.toBase58(),
        manager: NTT_ADDRESS,
        transceiver: {
          wormhole: NTT_ADDRESS,
        },
      },
    });

    tokenAccount = await spl.createAssociatedTokenAccount(
      connection,
      payer,
      mint,
      payer.publicKey
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

  describe("Locking", () => {
    beforeAll(async () => {
      await spl.setAuthority(
        connection,
        payer,
        mint,
        owner,
        0, // mint
        ntt.pdas.tokenAuthority()
      );

      // init
      const initTxs = ntt.initialize({
        payer,
        owner: payer,
        chain: "Solana",
        mint,
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

      // Set Wormhole xcvr peer
      const setXcvrPeerTxs = ntt.setWormholeTransceiverPeer(remoteXcvr, sender);
      await signSendWait(ctx, setXcvrPeerTxs, signer);

      // Set manager peer
      const setPeerTxs = ntt.setPeer(remoteMgr, 18, 1000000n, sender);
      await signSendWait(ctx, setPeerTxs, signer);
    });

    test("Can send tokens", async () => {
      // TODO: factor out this test so it can be reused for burn&mint
      // transfer some tokens
      const amount = 100000n;
      const sender = Wormhole.parseAddress("Solana", signer.address());

      // made up receiver
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

      const unsignedVaa = (await coreBridge.parsePostMessageAccount(
        wormholeMessage
      )) as VAA<"Uint8Array">; // TODO: remove `as` when next version sdk is out

      const transceiverMessage = deserializePayload(
        "Ntt:WormholeTransfer",
        unsignedVaa.payload
      );

      // assert theat amount is what we expect
      expect(
        transceiverMessage.nttManagerPayload.payload.trimmedAmount
      ).toMatchObject({ amount: 10000n, decimals: 8 });

      // get from balance
      const balance = await connection.getTokenAccountBalance(tokenAccount);
      expect(balance.value.amount).toBe("9900000");

      // grab logs
      //await connection.confirmTransaction(redeemTx, "confirmed");
      //const tx = await anchor
      //  .getProvider()
      //  .connection.getParsedTransaction(redeemTx, {
      //    commitment: "confirmed",
      //  });
      // console.log(tx);
      // const log = tx.meta.logMessages[1];
      // const message = log.substring(log.indexOf(':') + 1);
      // console.log(message);
      // TODO: assert other stuff in the message
      // console.log(nttManagerMessage);
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
        return;
      }

      // expect(released).to.equal(true);
    });
  });

  describe("Static Checks", () => {
    const wh = new Wormhole("Testnet", [SolanaPlatform]);

    const overrides = {
      Solana: {
        token: "EetppHswYvV1jjRWoQKC1hejdeBDHR9NNzNtCyRQfrrQ",
        manager: "NTtAaoDJhkeHeaVUHnyhwbPNAN6WgBpHkHBTc6d7vLK",
        transceiver: {
          wormhole: "ExVbjD8inGXkt7Cx8jVr4GF175sQy1MeqgfaY53Ah8as",
        },
      },
    };

    describe("ABI Versions Test", function () {
      const ctx = wh.getChain("Solana");
      test("It initializes from Rpc", async function () {
        const ntt = await SolanaNtt.fromRpc(await ctx.getRpc(), {
          Solana: {
            ...ctx.config,
            contracts: {
              ...ctx.config.contracts,
              ...{ ntt: overrides["Solana"] },
            },
          },
        });
        expect(ntt).toBeTruthy();
      });

      test("It initializes from constructor", async function () {
        const ntt = new SolanaNtt("Testnet", "Solana", await ctx.getRpc(), {
          ...ctx.config.contracts,
          ...{ ntt: overrides["Solana"] },
        });
        expect(ntt).toBeTruthy();
      });

      test("It gets the correct version", async function () {
        // TODO: need valida address with lamports on network

        const { manager } = overrides["Solana"];
        const version = await SolanaNtt._getVersion(
          manager,
          await ctx.getRpc(),
          new SolanaAddress(payer.publicKey.toBase58())
        );
        expect(version).toBe("1.0.0");
      });
    });
  });

  // describe('Burning', () => {
  //   beforeEach(async () => {
  //     await ntt.initialize({
  //       payer,
  //       owner,
  //       chain: 'solana',
  //       mint,
  //       outboundLimit: new BN(1000000),
  //       mode: 'burning'
  //     })
  //   });
  // });
});

import * as anchor from "@coral-xyz/anchor";
import * as spl from "@solana/spl-token";
import {
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
  encoding,
} from "@wormhole-foundation/sdk";
import * as testing from "@wormhole-foundation/sdk-definitions/testing";
import {
  SolanaPlatform,
  getSolanaSignAndSendSigner,
} from "@wormhole-foundation/sdk-solana";
import * as fs from "fs";
import { SolanaNtt } from "../ts/sdk/index.js";
import { handleTestSkip, signSendWait } from "./utils/index.js";

handleTestSkip(__filename);

const solanaRootDir = `${__dirname}/../`;

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

const receiver = testing.utils.makeUniversalChainAddress("Ethereum");

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

const mintAuthority = anchor.web3.Keypair.generate();
const mintKeypair = anchor.web3.Keypair.generate();
const mint = mintKeypair.publicKey;
const transferFeeConfigAuthority = anchor.web3.Keypair.generate();
const withdrawWithheldAuthority = anchor.web3.Keypair.generate();
const decimals = 9;
const feeBasisPoints = 50;
const maxFee = BigInt(5_000);
const mintAmount = BigInt(1_000_000_000);

const transferAmount = 100_000n;

let signer: Signer;
let sender: AccountAddress<"Solana">;
let ntt: SolanaNtt<"Devnet", "Solana">;
let tokenAccount: anchor.web3.PublicKey;
let tokenAddress: string;

const TOKEN_PROGRAM = spl.TOKEN_2022_PROGRAM_ID;

describe("example-native-token-transfers", () => {
  describe("Transfer Fee Locking", () => {
    beforeAll(async () => {
      try {
        signer = await getSolanaSignAndSendSigner(connection, payer, {
          //debug: true,
        });
        sender = Wormhole.parseAddress("Solana", signer.address());

        // initialize mint
        const extensions = [spl.ExtensionType.TransferFeeConfig];
        const mintLen = spl.getMintLen(extensions);
        const lamports = await connection.getMinimumBalanceForRentExemption(
          mintLen
        );
        const transaction = new Transaction().add(
          SystemProgram.createAccount({
            fromPubkey: payer.publicKey,
            newAccountPubkey: mint,
            space: mintLen,
            lamports,
            programId: TOKEN_PROGRAM,
          }),
          spl.createInitializeTransferFeeConfigInstruction(
            mint,
            transferFeeConfigAuthority.publicKey,
            withdrawWithheldAuthority.publicKey,
            feeBasisPoints,
            maxFee,
            TOKEN_PROGRAM
          ),
          spl.createInitializeMintInstruction(
            mint,
            decimals,
            mintAuthority.publicKey,
            null,
            TOKEN_PROGRAM
          )
        );
        await sendAndConfirmTransaction(
          connection,
          transaction,
          [payer, mintKeypair],
          undefined
        );

        // create and fund token account
        tokenAccount = await spl.createAccount(
          connection,
          payer,
          mint,
          payer.publicKey,
          undefined,
          undefined,
          TOKEN_PROGRAM
        );
        await spl.mintTo(
          connection,
          payer,
          mint,
          tokenAccount,
          mintAuthority,
          mintAmount,
          [],
          undefined,
          TOKEN_PROGRAM
        );

        // create our contract client
        tokenAddress = mint.toBase58();
        ntt = new SolanaNtt("Devnet", "Solana", connection, {
          ...ctx.config.contracts,
          ntt: {
            token: tokenAddress,
            manager: NTT_ADDRESS,
            transceiver: { wormhole: NTT_ADDRESS },
          },
        });

        // transfer mint authority to ntt
        await spl.setAuthority(
          connection,
          payer,
          mint,
          mintAuthority,
          spl.AuthorityType.MintTokens,
          ntt.pdas.tokenAuthority(),
          [],
          undefined,
          TOKEN_PROGRAM
        );

        // init
        const initTxs = ntt.initialize(sender, {
          mint,
          outboundLimit: 100_000_000n,
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
        const setPeerTxs = ntt.setPeer(remoteMgr, 18, 10_000_000n, sender);
        await signSendWait(ctx, setPeerTxs, signer);
      } catch (e) {
        console.error("Failed to setup peer: ", e);
        throw e;
      }
    });

    it("Returns with BadAmountAfterTransfer error", async () => {
      try {
        // TODO: keep or remove the `outboxItem` param?
        // added as a way to keep tests the same but it technically breaks the Ntt interface
        const outboxItem = anchor.web3.Keypair.generate();
        const xferTxs = ntt.transfer(
          sender,
          transferAmount,
          receiver,
          { queue: false, automatic: false, gasDropoff: 0n },
          outboxItem
        );
        await signSendWait(ctx, xferTxs, signer, false, true);
      } catch (e) {
        const error = anchor.AnchorError.parse(
          (e as anchor.AnchorError).logs
        )?.error;
        expect(error?.errorMessage).toBe("BadAmountAfterTransfer");
      }
    });
  });
});

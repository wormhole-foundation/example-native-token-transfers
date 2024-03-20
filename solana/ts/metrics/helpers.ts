import {
  createApproveInstruction,
  createAssociatedTokenAccountInstruction,
  createTransferCheckedInstruction,
  getAssociatedTokenAddressSync,
} from "@solana/spl-token";
import {
  Connection,
  Keypair,
  PublicKey,
  RpcResponseAndContext,
  SignatureStatus,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import fs from "fs";
import { NTT } from "../../ts/sdk";
import { BN } from "@coral-xyz/anchor";

export async function airdrop(
  testWalletLocation: string,
  connection: Connection
) {
  console.log("Airdropping to test wallet");
  const testWallet = Keypair.fromSecretKey(
    Uint8Array.from(JSON.parse(fs.readFileSync(testWalletLocation).toString()))
  );
  const tx = await connection.requestAirdrop(testWallet.publicKey, 1e9);
  const latestBlockHash = await connection.getLatestBlockhash();

  await connection.confirmTransaction({
    blockhash: latestBlockHash.blockhash,
    lastValidBlockHeight: latestBlockHash.lastValidBlockHeight,
    signature: tx,
  });
  console.log("Airdrop complete");
}

export function createInitializeTransaction(
  fromWallet: Keypair,
  toWallet: Keypair,
  mint: PublicKey,
  recentBlockhash: string,
  testTransferAmount: number
): Transaction {
  let instructions: TransactionInstruction[] = [];
  instructions.push(seedWalletInstruction(fromWallet, toWallet, 100000000)); // 10 million lamports seems safe
  instructions = instructions.concat(
    seedNttTestToken(mint, fromWallet, toWallet, testTransferAmount * 3)
  );

  const output = new Transaction();
  output.recentBlockhash = recentBlockhash;
  output.add(instructions[0], instructions[1], instructions[2]);
  output.sign(fromWallet);

  return output;
}

function seedWalletInstruction(
  fromWallet: Keypair,
  toWallet: Keypair,
  walletSeedSol: number
): TransactionInstruction {
  return SystemProgram.transfer({
    fromPubkey: fromWallet.publicKey,
    toPubkey: toWallet.publicKey,
    lamports: walletSeedSol,
  });
}

export function getAssociatedTokenAccount(mint, owner) {
  const tokenAccount = getAssociatedTokenAddressSync(mint, owner, true);

  return tokenAccount;
}

function seedNttTestToken(
  mint: PublicKey,
  fromWallet: Keypair,
  toWallet: Keypair,
  seedNttTokenAmount: number
): TransactionInstruction[] {
  const defaultTargetAta = getAssociatedTokenAccount(mint, toWallet.publicKey);
  const defaultSourceAta = getAssociatedTokenAccount(
    mint,
    fromWallet.publicKey
  );

  // console.log("debug: defaultTargetAta: ", defaultTargetAta.toBase58());
  // console.log("debug: defaultSourceAta: ", defaultSourceAta.toBase58());
  // console.log("debug: mint: ", mint.toBase58());
  //First create an associated token account for the toWallet for the mint
  const createAtaInstruction = createAssociatedTokenAccountInstruction(
    fromWallet.publicKey,
    defaultTargetAta,
    toWallet.publicKey,
    mint
  );

  //Second add a simple SPL transfer to the ATA for specified amount of the mint
  const transferInstruction = createTransferCheckedInstruction(
    defaultSourceAta,
    mint,
    defaultTargetAta,
    fromWallet.publicKey,
    seedNttTokenAmount,
    9 //Assume token has 9 decimals
  );

  //Tested that the funds can be sent back using the toWallet as owner signer, and the answer is yes
  // const transferInstruction2 = createTransferCheckedInstruction(
  //   defaultTargetAta,
  //   mint,
  //   defaultSourceAta,
  //   toWallet.publicKey,
  //   seedNttTokenAmount,
  //   9 //Assume token has 9 decimals
  // );

  //return the instructions
  return [createAtaInstruction, transferInstruction];
}

export async function createNttBridgeTestTransaction(
  connection: Connection,
  fromWallet: Keypair,
  recentBlockhash: string,
  nttId: string,
  wormholeId: string,
  mint: PublicKey,
  amount: number
): Promise<Transaction> {
  const outboxKeypair = Keypair.generate();

  const ntt = new NTT(connection, {
    nttId: nttId as any,
    wormholeId: wormholeId as any,
  });
  const nttConfig = await ntt.getConfig();
  const defaultSourceAta = getAssociatedTokenAccount(
    mint,
    fromWallet.publicKey
  );
  // const bridgeOwnerAcc = "worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth";
  // const bridgeOppAcc = "2yVjuQwpsvdsrywzsJJVs9Ueh4zayyo5DYJbBNc3DDpn";
  // const bridgeOwnerPull = await connection.getAccountInfo(
  //   new PublicKey(bridgeOwnerAcc)
  // );
  // const bridgeOppPull = await connection.getAccountInfo(
  //   new PublicKey(bridgeOppAcc)
  // );
  // console.log("debug: bridgeOwnerPull: ", JSON.stringify(bridgeOwnerPull));
  // console.log("debug: bridgeOppPull: ", JSON.stringify(bridgeOppPull));

  // console.log("debug: mint: ", mint.toBase58());
  // console.log("debug: defaultSourceAta: ", defaultSourceAta.toBase58());
  // await connection
  //   .getAccountInfo(defaultSourceAta, { commitment: "confirmed" })
  //   .then((info) => {
  //     if (info === null) {
  //       throw new Error("Source ATA not found");
  //     } else {
  //       console.log("debug: Source ATA found!");
  //       console.log("account size : " + info.data.length);
  //       console.log("account owner : " + info.owner.toBase58());
  //       console.log("fromWallet pubkey: " + fromWallet.publicKey.toBase58());
  //     }
  //   });
  // await ntt.getConfig().then((config) => {
  //   console.log("debug: NTT config: ", JSON.stringify(config));
  // });
  //const transceiverAcc = await ntt.registeredTransceiverAddress(new PublicKey("nttiK1SepaQt6sZ4WGW5whvc9tEnGXGxuKeptcQPCcS"));
  // console.log(
  //   "balance of source ATA: ",
  //   await connection.getTokenAccountBalance(defaultSourceAta, "confirmed")
  // );
  // const parsedTokenAccount = await connection.getParsedAccountInfo(
  //   defaultSourceAta,
  //   "confirmed"
  // );
  // console.log(
  //   "parsedTokenAccount for source ATA: ",
  //   JSON.stringify(parsedTokenAccount)
  // );
  const approveIx = createApproveInstruction(
    defaultSourceAta,
    ntt.sessionAuthorityAddress(fromWallet.publicKey, {
      amount: new BN(amount),
      recipientChain: { id: 2 },
      recipientAddress: Array.from(fromWallet.publicKey.toBuffer()),
      shouldQueue: false,
    }),
    fromWallet.publicKey,
    BigInt(amount.toString())
  );
  const createTransferLockInstruction = await ntt.createTransferLockInstruction(
    {
      payer: fromWallet.publicKey,
      from: defaultSourceAta,
      fromAuthority: fromWallet.publicKey,
      amount: new BN(amount),
      recipientChain: "ethereum", //we aren't going to redeem anyway
      recipientAddress: Array.from(fromWallet.publicKey.toBuffer()), // TODO: dummy
      shouldQueue: false,
      outboxItem: outboxKeypair.publicKey,
      config: nttConfig,
    }
  );

  const outboundInstruction = await ntt.createReleaseOutboundInstruction({
    payer: fromWallet.publicKey,
    outboxItem: outboxKeypair.publicKey,
    revertOnDelay: true,
  });

  // console.log("debug");
  // console.log("FromWallet PublicKey: ", fromWallet.publicKey.toBase58());
  // console.log("OutboxKeypair PublicKey: ", outboxKeypair.publicKey.toBase58());
  // console.log("default ATA address: ", defaultSourceAta.toBase58());

  const output = new Transaction();
  output.add(approveIx, createTransferLockInstruction, outboundInstruction);
  output.recentBlockhash = recentBlockhash;
  console.log("debug: output: ", JSON.stringify(output, null, 2));
  output.sign(fromWallet, outboxKeypair);

  return output;
}

export function bulkFetchTxSignatures(
  connection: Connection,
  signatures: string[]
): Promise<RpcResponseAndContext<SignatureStatus | null>>[] {
  return signatures.map((signature) =>
    connection.getSignatureStatus(signature)
  );
}

export function transactionBulkBroadcast(
  transactions: Transaction[],
  connection: Connection
): Promise<string>[] {
  return transactions.map((transaction) =>
    connection.sendRawTransaction(transaction.serialize(), {
      skipPreflight: true,
    })
  );
}

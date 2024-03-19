import {
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
  recentBlockhash: string
): Transaction {
  let instructions: TransactionInstruction[] = [];
  instructions.push(seedWalletInstruction(fromWallet, toWallet, 10000000)); // 10 million lamports seems safe
  instructions = instructions.concat(
    seedNttTestToken(mint, fromWallet, toWallet, 1000)
  ); // 1000 seems safe

  console.log("debug: instructions: ", JSON.stringify(instructions));

  const output = new Transaction();
  output.recentBlockhash = recentBlockhash;
  output.add(instructions[0], instructions[1], instructions[2]);
  output.sign(fromWallet);

  console.log("debug: output: ", JSON.stringify(output));
  return output;
}

function seedWalletInstruction(
  fromWallet: Keypair,
  toWallet: Keypair,
  amount: number
): TransactionInstruction {
  return SystemProgram.transfer({
    fromPubkey: fromWallet.publicKey,
    toPubkey: toWallet.publicKey,
    lamports: amount,
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
  amount: number
): TransactionInstruction[] {
  const defaultTargetAta = getAssociatedTokenAccount(mint, toWallet.publicKey);
  const defaultSourceAta = getAssociatedTokenAccount(
    mint,
    fromWallet.publicKey
  );

  console.log("debug: defaultTargetAta: ", defaultTargetAta.toBase58());
  console.log("debug: defaultSourceAta: ", defaultSourceAta.toBase58());
  console.log("debug: mint: ", mint.toBase58());
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
    amount,
    9 //Assume token has 9 decimals
  );

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
  const defaultSourceAta = getAssociatedTokenAccount(
    mint,
    fromWallet.publicKey
  );
  console.log("debug: defaultSourceAta: ", defaultSourceAta.toBase58());

  await connection.getAccountInfo(defaultSourceAta).then((info) => {
    if (info === null) {
      throw new Error("Source ATA not found");
    } else {
      console.log("debug: Source ATA found!");
      console.log("account size : " + info.data.length);
    }
  });

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
    }
  );

  const outboundInstruction = await ntt.createReleaseOutboundInstruction({
    payer: fromWallet.publicKey,
    outboxItem: outboxKeypair.publicKey,
    revertOnDelay: false,
  });

  // console.log("debug");
  // console.log("FromWallet PublicKey: ", fromWallet.publicKey.toBase58());
  // console.log("OutboxKeypair PublicKey: ", outboxKeypair.publicKey.toBase58());
  // console.log("default ATA address: ", defaultSourceAta.toBase58());

  const output = new Transaction();
  output.add(createTransferLockInstruction, outboundInstruction);
  output.recentBlockhash = recentBlockhash;
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

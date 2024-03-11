import {
  Connection,
  TransactionInstruction,
  TransactionMessage,
  VersionedTransaction,
  Keypair,
  PublicKey,
} from "@solana/web3.js";

export async function buildTransaction({
  connection,
  payer,
  signers,
  instructions,
}: {
  connection: Connection;
  payer: PublicKey;
  signers: Keypair[];
  instructions: TransactionInstruction[];
}): Promise<VersionedTransaction> {
  let blockhash = await connection.getLatestBlockhash().then(res => res.blockhash);

  const messageV0 = new TransactionMessage({
    payerKey: payer,
    recentBlockhash: blockhash,
    instructions,
  }).compileToV0Message();

  const tx = new VersionedTransaction(messageV0);

  tx.sign(signers);
  // signers.forEach(s => tx.sign([s]));

  return tx;
}
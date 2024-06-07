import {
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";

import { SolanaSigner, connection, getSigner } from "./env";

export async function ledgerSignAndSend(
  instructions: TransactionInstruction[],
  signers: Keypair[]
) {
  const deployerSigner = await getSigner();
  const deployerPk = new PublicKey(await deployerSigner.getAddress());

  const tx = new Transaction();
  tx.add(...instructions);

  const recentBlockHash = await connection.getRecentBlockhash();

  tx.recentBlockhash = recentBlockHash.blockhash;
  tx.feePayer = deployerPk;

  signers.forEach((signer) => tx.partialSign(signer));

  await addLedgerSignature(tx, deployerSigner, deployerPk);

  return connection.sendRawTransaction(tx.serialize(), {
    skipPreflight: true,
  });
}

export async function addLedgerSignature(
  tx: Transaction,
  signer: SolanaSigner,
  signerPk: PublicKey
) {
  const signedByPayer = await signer.signTransaction(
    tx.compileMessage().serialize()
  );
  tx.addSignature(signerPk, signedByPayer);
}

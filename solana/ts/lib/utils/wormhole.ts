import * as anchor from "@coral-xyz/anchor";
import {
  Chain,
  Network,
  SignAndSendSigner,
  TransactionId,
  TxHash,
  UnsignedTransaction,
  VAA,
  Wormhole,
  isSigner,
} from "@wormhole-foundation/sdk-connect";
import { getSolanaSignAndSendSigner } from "@wormhole-foundation/sdk-solana";
import { SolanaWormholeCore } from "@wormhole-foundation/sdk-solana-core";

export async function postVaa(
  connection: anchor.web3.Connection,
  payer: anchor.web3.Keypair,
  vaa: VAA,
  coreBridgeAddress: anchor.web3.PublicKey
) {
  const core = new SolanaWormholeCore("Devnet", "Solana", connection, {
    coreBridge: coreBridgeAddress.toBase58(),
  });

  const signer = (await getSolanaSignAndSendSigner(
    connection,
    payer
  )) as SignAndSendSigner<"Devnet", "Solana">;

  const sender = Wormhole.parseAddress(signer.chain(), signer.address());

  const txs = core.postVaa(sender, vaa);
  await signSendWait(txs, signer);
}

export async function signSendWait<N extends Network, C extends Chain>(
  xfer: AsyncGenerator<UnsignedTransaction<N, C>>,
  signer: SignAndSendSigner<N, C>
): Promise<TransactionId[]> {
  const txHashes: TxHash[] = [];

  if (!isSigner(signer))
    throw new Error("Invalid signer, not SignAndSendSigner or SignOnlySigner");

  let txbuff: UnsignedTransaction<N, C>[] = [];
  for await (const tx of xfer) {
    if (tx.parallelizable) {
      txbuff.push(tx);
    } else {
      if (txbuff.length > 0) {
        txHashes.push(...(await signer.signAndSend(txbuff)));
        txbuff = [];
      }
      txHashes.push(...(await signer.signAndSend([tx])));
    }
  }

  if (txbuff.length > 0) {
    txHashes.push(...(await signer.signAndSend(txbuff)));
  }

  return txHashes.map((txid) => ({ chain: signer.chain(), txid }));
}

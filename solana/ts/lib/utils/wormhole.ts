import * as anchor from "@coral-xyz/anchor";
import {
  SignAndSendSigner,
  VAA,
  Wormhole,
  signAndSendWait,
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
  return await signAndSendWait(txs, signer);
}

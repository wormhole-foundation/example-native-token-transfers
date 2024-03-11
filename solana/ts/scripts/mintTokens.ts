import { createAssociatedTokenAccount, mintTo } from "@solana/spl-token";
import { PublicKey } from "@solana/web3.js";

import { connection, deployerKeypair, mintRecipientAddress, mintAddress } from "./env";

if (!mintRecipientAddress) {
  throw new Error("MINT_RECIPIENT_ADDRESS is not set");
}
const mintRecipient = new PublicKey(mintRecipientAddress);

if (!mintAddress) {
  throw new Error("MINT_ADDRESS is not set");
}

const mint = new PublicKey(mintAddress);

(async () => {
  let ata;

  // TODO: gracefully handle cases where ata already exists...
  try {
    ata = await createAssociatedTokenAccount(connection, deployerKeypair, mint, mintRecipient);
    console.log("Created ATA ad address:", ata.toBase58());
  } catch (err) {
    console.error("Failed to create ATA");
    throw err;
  }

  try {
    await mintTo(connection, deployerKeypair, mint, ata, deployerKeypair.publicKey, BigInt(100000000000000));
    console.log("Tokens minted successfully.");
  } catch (error) {
    console.error("Failed to mint tokens");
    throw error;
  }
})();


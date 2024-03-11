import { MINT_SIZE, TOKEN_PROGRAM_ID, createInitializeMint2Instruction } from "@solana/spl-token";
import {
  SystemProgram,
  Keypair,
} from "@solana/web3.js";

import { connection, deployerKeypair } from "./env";
import { buildTransaction } from "./helpers";

const mintKeypair = Keypair.generate();

(async () => {
  const tokenConfig = {
    decimals: 9,
    name: "Test NTT Token",
    symbol: "TEST_NTT_TKN",
    uri: "https://thisisnot.arealurl/info.json",
  };

  const createMintAccountInstruction = SystemProgram.createAccount({
    fromPubkey: deployerKeypair.publicKey,
    newAccountPubkey: mintKeypair.publicKey,
    space: MINT_SIZE,
    lamports: await connection.getMinimumBalanceForRentExemption(MINT_SIZE),
    programId: TOKEN_PROGRAM_ID,
  });

  const initializeMintInstruction = createInitializeMint2Instruction(
    mintKeypair.publicKey,
    tokenConfig.decimals,
    deployerKeypair.publicKey,
    null,
  );

  // const accountMetadataInstruction = getCreateMetadataAccountInstruction(tokenConfig);

  const tx = await buildTransaction({
    connection,
    payer: deployerKeypair.publicKey,
    signers: [deployerKeypair, mintKeypair],
    instructions: [
      createMintAccountInstruction,
      initializeMintInstruction,
      // accountMetadataInstruction,
    ],
  });


  try {
    const sig = await connection.sendTransaction(tx);
  } catch (err) {
    console.error("Failed to send transaction:");
    console.log(tx);

    throw err;
  }
})();

// TODO: Finish this function to add account metadata to the token
// function getCreateMetadataAccountInstruction(tokenConfig) {
//   // const metadataAccount = PublicKey.findProgramAddressSync(
//   //   [Buffer.from("metadata"), METADATA_PROGRAM_ID.toBuffer(), mintKeypair.publicKey.toBuffer()],
//   //   METADATA_PROGRAM_ID,
//   // )[0];

//   // console.log("Metadata address:", metadataAccount.toBase58());

//   const createAccountArgs = {
//     // metadata: metadataAccount,
//     mint: mintKeypair.publicKey,
//     mintAuthority: deployerKeypair.publicKey,
//     payer: deployerKeypair.publicKey,
//     updateAuthority: deployerKeypair.publicKey,
//     // rent?
//     data: {
//       creators: null,
//       name: tokenConfig.name,
//       symbol: tokenConfig.symbol,
//       uri: tokenConfig.uri,
//       sellerFeeBasisPoints: 0,
//       collection: null,
//       uses: null,
//     },
//     // `collectionDetails` - for non-nft type tokens, normally set to `null` to not have a value set
//     collectionDetails: null,
//     isMutable: false,
//   };

//   const context = createUmi(rpcUrl);

//   return createMetadataAccountV3(context, createAccountArgs);
// }


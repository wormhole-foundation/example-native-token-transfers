

import { PublicKey,  } from "@solana/web3.js";
import { BN } from "@coral-xyz/anchor";

import { connection, getSigner, getProgramAddresses } from "./env";
import { NTT } from "../sdk";
import { ledgerSignAndSend } from "./helpers";
import { NTTGovernance } from "../sdk/governance";

(async () => {
  const { nttProgramId, wormholeProgramId } = getProgramAddresses();

  const signer = await getSigner();
  const signerPk = new PublicKey(await signer.getAddress());

  const ntt = new NTT(connection, {
    nttId: nttProgramId as any,
    wormholeId: wormholeProgramId as any,
  });

  const claimOwnershipIx = await ntt.createClaimOwnershipInstruction({
    owner: signerPk,
  });

  console.log(`Account ${signerPk.toBase58()} is claiming ownership of NTT Program ${nttProgramId}.`);

  const signature = await ledgerSignAndSend([claimOwnershipIx], []);

  await connection.confirmTransaction(signature);
  console.log("Success.");
})();


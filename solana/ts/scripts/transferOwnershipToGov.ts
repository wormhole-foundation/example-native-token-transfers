

import { PublicKey,  } from "@solana/web3.js";
import { BN } from "@coral-xyz/anchor";

import { connection, getSigner, getNttConfiguration, getGovernanceConfiguration } from "./env";
import { NTT } from "../sdk";
import { ledgerSignAndSend } from "./helpers";
import { NTTGovernance } from "../sdk/governance";

(async () => {
  const { programId: govProgramId } = getGovernanceConfiguration();
  const { wormholeProgramId, programId: nttProgramId } = getNttConfiguration();

  const ntt = new NTT(connection, {
    nttId: nttProgramId as any,
    wormholeId: wormholeProgramId as any,
  });

  const governance = new NTTGovernance(connection, {
    programId: govProgramId as any,
  });

  const signer = await getSigner();
  const signerPk = new PublicKey(await signer.getAddress());
  
  const governancePda = governance.governanceAccountAddress();

  const transferOwnershipIx = await ntt.createTransferOwnershipInstruction({
    owner: signerPk,
    newOwner: governancePda,
  });

  console.log(`Transferring NTT Program ${nttProgramId} ownership to ${governancePda.toBase58()} derived from(${govProgramId}).`);

  const signature = await ledgerSignAndSend([transferOwnershipIx], []);

  await connection.confirmTransaction(signature);
  console.log("Success.");
})();


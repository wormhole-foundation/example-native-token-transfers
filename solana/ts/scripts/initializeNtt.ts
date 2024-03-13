
import { setAuthority } from "@solana/spl-token";
import { BN } from '@coral-xyz/anchor'
import { PublicKey } from "@solana/web3.js";

import { NTT } from "../sdk";
import { connection, deployerKeypair, mintAddress, wormholeProgramId, nttProgramId } from "./env";

if (!mintAddress) {
  throw new Error("MINT_ADDRESS is not set");
}
const mint = new PublicKey(mintAddress);

if (!wormholeProgramId) {
  throw new Error("WORMHOLE_PROGRAM_ID is not set");
}

if (!nttProgramId) {
  throw new Error("NTT_PROGRAM_ID is not set");
}

(async () => {
  const ntt = new NTT(connection, {
    nttId: nttProgramId as any,
    wormholeId: wormholeProgramId as any,
  });

  const nttManagerPk = ntt.tokenAuthorityAddress();

  // make ntt-manager the mint authority
  // TODO: this will fail if the authority has already been set
  await setAuthority(
    connection, 
    deployerKeypair, 
    mint, 
    deployerKeypair.publicKey, 
    0, 
    nttManagerPk,
  );
  console.log(`Authority set to ${nttManagerPk.toBase58()}`);
  
  console.log("Manager Emitter Address:", await ntt.emitterAccountAddress().toBase58());

  await ntt.initialize({
    payer: deployerKeypair,
    owner: deployerKeypair,
    chain: "solana",
    mint,
    // TODO: this two properties should also be configurable
    outboundLimit: new BN(10000000000000),
    mode: "locking",
  });
  console.log("NTT initialized succesfully!");

  await ntt.registerTransceiver({
    payer: deployerKeypair,
    owner: deployerKeypair,
    transceiver: new PublicKey(ntt.program.programId),
  });
  console.log(`Transceiver registered at: ${ntt.program.programId}`);

})();


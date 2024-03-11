
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

  // make ntt-manager the mint authority
  await setAuthority(
    connection, 
    deployerKeypair, 
    mint, 
    deployerKeypair, 
    0, 
    ntt.tokenAuthorityAddress()
  );

  // initialize the ntt manager
  await ntt.initialize({
    payer: deployerKeypair,
    owner: deployerKeypair,
    chain: "solana",
    mint,
    // TODO: this two properties should also be configurable
    outboundLimit: new BN(1000000),
    mode: "locking",
  });

  // register ntt manager id as it's own transceiver
  await ntt.registerTransceiver({
    payer: deployerKeypair,
    owner: deployerKeypair,
    transceiver: nttProgramId as any,
  });
})();


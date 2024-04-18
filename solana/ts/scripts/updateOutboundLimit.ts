

import { PublicKey } from "@solana/web3.js";

import { connection, outboundLimit, getEnv, getSigner } from "./env";
import { NTT } from "../sdk";
import { ledgerSignAndSend } from "./helpers";

(async () => {
  const ntt = new NTT(connection, {
    nttId: getEnv("NTT_PROGRAM_ID") as any,
    wormholeId: getEnv("WORMHOLE_PROGRAM_ID") as any,
  });

  const signer = await getSigner();
  const signerPk = new PublicKey(await signer.getAddress());

  const setOutboundLimitIx = await ntt.createSetoutboundLimitInstruction({
    owner: signerPk,
    limit: outboundLimit,
  });

  const signature = await ledgerSignAndSend([setOutboundLimitIx], []);

  console.log(`Outbound limit set to ${outboundLimit} with tx ${signature}`);
  await connection.confirmTransaction(signature);
  console.log("Success.");
})();


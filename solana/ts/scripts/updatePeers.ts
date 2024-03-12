
import { BN } from '@coral-xyz/anchor'
import { coalesceChainName, tryHexToNativeString, tryNativeToHexString } from "@certusone/wormhole-sdk";

import { connection, deployerKeypair, evmNttDeployments, wormholeProgramId, nttProgramId } from "./env";
import { NTT } from "../sdk";

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

  for (const deployment of evmNttDeployments) {
    const { chainId, transceiverAddress, managerAddress, tokenDecimals, limit } = deployment;
    const chainName = coalesceChainName(deployment.chainId);
    console.log("Configuring peers for chain " + chainId);

    if (!transceiverAddress || !managerAddress || !tokenDecimals || !chainName || chainName === "unset") {
      console.error(`Invalid deployment configuration for chainId ${chainId}`);
      continue;
    }

    try {
      const normalizedTransceiverAddress = tryNativeToHexString(transceiverAddress, chainName);
      await ntt.setWormholeTransceiverPeer({
        payer: deployerKeypair,
        owner: deployerKeypair,
        chain: chainName,
        address: Buffer.from(normalizedTransceiverAddress, "hex"),
      });
      console.log(`Configured peer address for ${chainId}: ${normalizedTransceiverAddress}`);
    } catch (error) {
      console.error(`Failed to configure manager peer address for ${chainId}: ${error}`);
      continue;
    }

    // // Set the evm manager as the manager peer
    try {
      const normalizedManagerAddress = tryNativeToHexString(managerAddress, chainName);
      await ntt.setPeer({
        payer: deployerKeypair,
        owner: deployerKeypair,
        chain: chainName,
        address: Buffer.from(normalizedManagerAddress, "hex"),
        limit: new BN(limit),
        tokenDecimals: tokenDecimals,
      });
      console.log(`Configured manager peer address for ${chainId}: ${normalizedManagerAddress}`);
    } catch (error) {
      console.error(`Failed to configure transceiver peer for ${chainId}: ${error}`);
      continue;
    }
  }
})();


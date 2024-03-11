
import { BN } from '@coral-xyz/anchor'
import { coalesceChainName, tryNativeToHexString } from "@certusone/wormhole-sdk";

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

    if (!transceiverAddress || !managerAddress || !tokenDecimals || !chainName || chainName === "unset") {
      console.error(`Invalid deployment configuration for chainId ${chainId}`);
      continue;
    }

    // Set evm transceiver as the transceiver peer
    try {
      const normalizedTransceiverAddress = tryNativeToHexString(transceiverAddress, chainName);
      await ntt.setWormholeTransceiverPeer({
        payer: deployerKeypair,
        owner: deployerKeypair,
        chain: chainName,
        address: Buffer.from(normalizedTransceiverAddress),
      });
      console.log(`Configured peer address for ${chainId}: ${normalizedTransceiverAddress}`);
    } catch (error) {
      console.error(`Failed to configure manager peer address for ${chainId}: ${error}`);
      continue;
    }

    // Set the evm manager as the manager peer
    try {
      const normalizedManagerAddress = tryNativeToHexString(managerAddress, chainName);
      await ntt.setPeer({
        payer: deployerKeypair,
        owner: deployerKeypair,
        chain: chainName,
        address: Buffer.from(normalizedManagerAddress),
        limit: new BN(limit),
        tokenDecimals: tokenDecimals,
      });
    } catch (error) {
      console.error(`Failed to configure transceiver peer for ${chainId}: ${error}`);
      continue;
    }
  }
})();


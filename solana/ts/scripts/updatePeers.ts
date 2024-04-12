
import { BN } from '@coral-xyz/anchor'
import { Keypair, PublicKey } from "@solana/web3.js";
import { ChainName, coalesceChainName, tryNativeToHexString } from "@certusone/wormhole-sdk";

import { connection, evmNttDeployments, getEnv, getSigner } from "./env";
import { NTT } from "../sdk";
import { ledgerSignAndSend } from './helpers';

(async () => {
  const ntt = new NTT(connection, {
    nttId: getEnv("NTT_PROGRAM_ID") as any,
    wormholeId: getEnv("WORMHOLE_PROGRAM_ID") as any,
  });

  const signer = await getSigner();
  const signerPk = new PublicKey(await signer.getAddress());

  for (const deployment of evmNttDeployments) {
    const { chainId, transceiverAddress, managerAddress, tokenDecimals, limit } = deployment;
    const chainName = coalesceChainName(deployment.chainId);
    console.log("Configuring peers for chain " + chainId);

    if (!transceiverAddress || !managerAddress || !tokenDecimals || !chainName || chainName === "unset") {
      console.error(`Invalid deployment configuration for chainId ${chainId}`);
      continue;
    }

    const wormholeMessage = Keypair.generate();

    const normalizedTransceiverAddress = tryNativeToHexString(transceiverAddress, chainName);
    const setTransceiverIxs = await ntt.createSetTransceiverPeerInstructions({
      chain: chainName as ChainName,
      payer: signerPk,
      owner: signerPk,
      address: Buffer.from(normalizedTransceiverAddress, "hex"),
      wormholeMessage,
    });
    console.log(`Configuring peer address for ${chainId}: ${normalizedTransceiverAddress}`);

    // // Set the evm manager as the manager peer
    const normalizedManagerAddress = tryNativeToHexString(managerAddress, chainName);
    const setPeerIx = await ntt.createSetPeerInstruction({
      payer: signerPk,
      owner: signerPk,
      chain: chainName,
      address: Buffer.from(normalizedManagerAddress, "hex"),
      limit: new BN(limit),
      tokenDecimals: tokenDecimals,
    });
    console.log(`Configuring manager peer address for ${chainId}: ${normalizedManagerAddress}`);

    try {
      await ledgerSignAndSend([...setTransceiverIxs, setPeerIx], [wormholeMessage]);
    } catch (error) {
      console.error(`Failed to configure chain ${chainId}. Error: ${error}`);
      continue;
    }

    console.log("Success.");
  }
})();


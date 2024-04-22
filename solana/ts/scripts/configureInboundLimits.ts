
import { BN } from '@coral-xyz/anchor'
import { Keypair, PublicKey } from "@solana/web3.js";
import { ChainName, coalesceChainName, tryNativeToHexString } from "@certusone/wormhole-sdk";

import { connection, getEvmNttDeployments, getNttConfiguration, getSigner } from "./env";
import { NTT } from "../sdk";
import { ledgerSignAndSend } from './helpers';

(async () => {
  const nttConfig = getNttConfiguration();
  const ntt = new NTT(connection, {
    nttId: nttConfig.programId as any,
    wormholeId: nttConfig.wormholeProgramId as any,
  });

  const signer = await getSigner();
  const signerPk = new PublicKey(await signer.getAddress());

  for (const deployment of getEvmNttDeployments()) {
    const { chainId, transceiverAddress, managerAddress, tokenDecimals, limit } = deployment;
    const chainName = coalesceChainName(deployment.chainId);
    const log = (...args) => console.log(`[${chainId}] `, ...args);

    if (!limit && limit !== 0) {
      console.error(`Invalid deployment configuration for chainId ${chainId}`);
      continue;
    }

    const ix = await ntt.createSetInboundLimitInstruction({
      owner: signerPk,
      limit: new BN(limit),
      chain: chainName,
    });

    log(`Configuring inbound limit to: ${limit}`);

    try {
      const txSignature = await ledgerSignAndSend([ix], []);
      log(`Transaction ${txSignature} sent.`);
      await connection.confirmTransaction(txSignature);
    } catch (error) {
      console.error(`Failed to configure chain ${chainId}. Error: ${error.toString()}`);
      continue;
    }

    console.log("Success.");
  }
})();


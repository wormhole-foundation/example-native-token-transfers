import { inspect } from "util";
import { NttQuoter } from "../sdk";
import { PublicKey, TransactionInstruction } from "@solana/web3.js";

import { connection, getSigner, getEnv, getQuoterConfiguration } from "./env";
import { ledgerSignAndSend } from "./helpers";

async function run() {
  const config = getQuoterConfiguration();
  const signer = await getSigner();
  const signerPk = new PublicKey(await signer.getAddress());

  const quoter = new NttQuoter(connection, config.nttQuoterProgramId);

  for (const managerConfig of config.managerRegistrations) {
    const nttKey = new PublicKey(managerConfig.programId);
    const registration = await quoter.tryGetRegisteredNtt(nttKey);
    const needsUpdate =
      registration !== null &&
      registration.gasCost !== managerConfig.gasCost &&
      registration.wormholeTransceiverIndex !==
        managerConfig.wormholeTransceiverIndex;
    const instructions = [] as TransactionInstruction[];
    if (registration !== null && (!managerConfig.isSupported || needsUpdate)) {
      console.log(`De-registering manager ${managerConfig.programId}`);
      instructions.push(
        await quoter.createDeregisterNttInstruction(signerPk, nttKey)
      );
    }

    if (managerConfig.isSupported) {
      if (managerConfig.gasCost === 0) {
        throw new Error(
          `Invalid manager configuration: ${inspect(managerConfig)}`
        );
      }

      console.log(`Registering manager ${managerConfig.programId}`);

      instructions.push(
        await quoter.createRegisterNttInstruction(
          signerPk,
          nttKey,
          managerConfig.gasCost,
          managerConfig.wormholeTransceiverIndex
        )
      );
    }

    try {
      
      const signature = await ledgerSignAndSend(instructions, []);
      await connection.confirmTransaction(signature, "confirmed");
      console.log("Success.");
    } catch (error) {
      console.error(
        `Failed to register or de-register manager ${managerConfig.programId}: ${error}`
      );
    }
  }
}

run();

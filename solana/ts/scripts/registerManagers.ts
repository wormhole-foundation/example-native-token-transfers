import { inspect } from 'util';
import { NttQuoter } from "../sdk";
import { PublicKey, TransactionInstruction } from "@solana/web3.js";

import { connection, getSigner, getEnv, managerRegistrations } from "./env";
import { ledgerSignAndSend } from "./helpers";

type ScriptConfig = {
  nttQuoterProgramId: string;
}

const config: ScriptConfig = {
  nttQuoterProgramId: getEnv("SOLANA_QUOTER_PROGRAM_ID"),
};

async function run() {
  const signer = await getSigner();
  const signerPk = new PublicKey(await signer.getAddress());

  const quoter = new NttQuoter(connection, config.nttQuoterProgramId);

  for (const { supportedManagers } of managerRegistrations) {
    for (const managerConfig of supportedManagers) {
      const nttKey = new PublicKey(managerConfig.programId);
      const registration = await quoter.tryGetRegisteredNtt(nttKey);
      const needsUpdate = registration !== null
        && registration.gasCost !== managerConfig.gasCost
        && registration.wormholeTransceiverIndex !== managerConfig.wormholeTransceiverIndex;
      const instructions = [] as TransactionInstruction[];
      if (registration !== null && (!managerConfig.isSupported || needsUpdate)) {
        instructions.push(await quoter.createDeregisterNttInstruction(
          signerPk,
          nttKey,
        ));
      }

      if (managerConfig.isSupported && needsUpdate) {
        if (managerConfig.gasCost === 0) {
          throw new Error(`Invalid manager configuration: ${inspect(managerConfig)}`);
        }

        instructions.push(await quoter.createRegisterNttInstruction(
          signerPk,
          nttKey,
          managerConfig.gasCost,
          managerConfig.wormholeTransceiverIndex,
        ));
      }

      try {
        await ledgerSignAndSend(instructions, []);
      } catch (error) {
        console.error(`Failed to register or de-register manager ${managerConfig.programId}: ${error}`);
      }
    }
  }
}


run();
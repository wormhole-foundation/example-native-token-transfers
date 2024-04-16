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
      let instruction: TransactionInstruction;
      if (!managerConfig.isSupported) {
        instruction = await quoter.createDeregisterNttInstruction(
          signerPk,
          new PublicKey(managerConfig.programId),
        );
      }

      else {
        if (!managerConfig.gasCost ||
          (!managerConfig.wormholeTransceiverIndex && managerConfig.wormholeTransceiverIndex !== 0)) {
          throw new Error(`Invalid manager configuration: ${inspect(managerConfig)}`);
        }

        instruction = await quoter.createRegisterNttInstruction(
          signerPk,
          new PublicKey(managerConfig.programId),
          managerConfig.gasCost,
          managerConfig.wormholeTransceiverIndex,
        );
      }

      try {
        await ledgerSignAndSend([instruction], []);
      } catch (error) {
        console.error(`Failed to register or de-register manager ${managerConfig.programId}: ${error}`);
      }
    }
  }
}


run();
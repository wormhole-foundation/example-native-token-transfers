import { Chain } from "@wormhole-foundation/sdk-base";
import { NttQuoter } from "../sdk";
import { PublicKey, Transaction } from "@solana/web3.js";

import { connection, getEnv } from "./env";
import { ledgerSignAndSend } from "./helpers";

interface InitConfig {
  /**
   * Fee recipient address encoded in base58.
   */
  feeRecipient: string;
  nttQuoterProgramId: string;
}

async function run() {
  const config: InitConfig = {
    feeRecipient: getEnv("SOLANA_QUOTER_FEE_RECIPIENT"),
    nttQuoterProgramId: getEnv("SOLANA_QUOTER_PROGRAM_ID"),
  };

  console.log(`Initializing program id: ${config.nttQuoterProgramId}`);

  const feeRecipient = new PublicKey(config.feeRecipient);

  const quoter = new NttQuoter(connection, config.nttQuoterProgramId);

  const  instanceState = await quoter.tryGetInstance();

  console.log("instanceState", instanceState !== null);

  const initInstruction = await quoter.createInitializeInstruction(feeRecipient);

  await ledgerSignAndSend([initInstruction], []);
}

run();
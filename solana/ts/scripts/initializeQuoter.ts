import { Chain } from "@wormhole-foundation/sdk-base";
import { NttQuoter } from "../sdk";
import { PublicKey, Transaction } from "@solana/web3.js";

import { connection, getEnv, getProgramAddresses, getQuoterConfiguration } from "./env";
import { ledgerSignAndSend } from "./helpers";

interface InitConfig {
  feeRecipient: string;
  nttQuoterProgramId: string;
}

async function run() {
  const programs = getProgramAddresses();
  const config = getQuoterConfiguration();

  console.log(`Initializing program id: ${programs.quoterProgramId}`);

  const feeRecipient = new PublicKey(config.feeRecipient);

  const quoter = new NttQuoter(connection, programs.quoterProgramId);

  const initInstruction = await quoter.createInitializeInstruction(feeRecipient);

  const signature = await ledgerSignAndSend([initInstruction], []);
  console.log("Transaction sent. Signature: ", signature);
  await connection.confirmTransaction(signature);
  console.log("Sucess. Signature: ", signature);
}

run();
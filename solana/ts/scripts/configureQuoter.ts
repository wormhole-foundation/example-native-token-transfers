import { Chain } from "@wormhole-foundation/sdk-base";
import { NttQuoter } from "../sdk";
import { PublicKey, TransactionInstruction } from "@solana/web3.js";

import { connection, getSigner, getEnv } from "./env";
import { ledgerSignAndSend } from "./helpers";

interface Config {
  /**
   * Fee recipient address encoded in base58.
   */
  feeRecipient: string;
  /**
   * Assistant address encoded in base58. This account is able to update prices in the contract.
   */
  assistant: string;
  /**
   * NTT quoter address encoded in base58.
   */
  nttQuoterProgramId: string;
  prices: Record<Chain, Quotes>;
}

interface Quotes {
  /**
   * Specified in Gwei per Eth units.
   */
  maxGasDropoffEth: string,
  /**
   * Specified in microdollars (10^-6 dollars).
   */
  basePriceUsd: string,
  /**
   * Specified in microdollars (10^-6 dollars).
   */
  nativePriceUsd: string,
  /**
   * Specified in wei per Gwei units.
   */
  gasPriceGwei: string,
}

async function run() {
  const signer = await getSigner();
  const signerPk = new PublicKey(await signer.getAddress());

  const config = {
    assistant: getEnv("SOLANA_QUOTER_ASSISTANT"),
    feeRecipient: getEnv("SOLANA_QUOTER_FEE_RECIPIENT"),
    nttQuoterProgramId: getEnv("SOLANA_QUOTER_PROGRAM_ID"),
  } as Config;

  const feeRecipient = new PublicKey(config.feeRecipient);
  const assistant = new PublicKey(config.assistant);

  const quoter = new NttQuoter(connection, config.nttQuoterProgramId);

  let instanceState = await quoter.tryGetInstance();

  if (instanceState === null) {
    throw new Error("Can't configure a quoter un-initialized.");
  }

  const configurationInstructions: TransactionInstruction[] = [];

  if (!instanceState.feeRecipient.equals(feeRecipient)) {
    const feeRecipientInstruction = await quoter.createSetFeeRecipientInstruction(instanceState, new PublicKey(config.feeRecipient));
    configurationInstructions.push(feeRecipientInstruction);
  }

  if (!instanceState.assistant.equals(assistant)) {
    const assistantInstruction = await quoter.createSetAssistantInstruction(instanceState, new PublicKey(config.assistant));
    configurationInstructions.push(assistantInstruction);
  } 

  // add any other global configs here...

  try {
    await ledgerSignAndSend(configurationInstructions, []);
  } catch (error) {
    console.error("Failed to configure quoter contract:", error);
  }

  for (const [chain, peer] of Object.entries(config.prices)) {
    try {
      await configurePeer(quoter, chain as Chain, peer, signerPk);
    } catch (error) {
      console.error(`Failed to configure ${chain} peer. Error: `, error);
    }
  }
}

async function configurePeer(quoter: NttQuoter, chain: Chain, peer: Quotes, signerPk: PublicKey) {
  const instructions: TransactionInstruction[] = [];
  let registeredChainInfo = await quoter.tryGetRegisteredChain(chain as Chain);
  if (registeredChainInfo === null) {
    instructions.push(await quoter.createRegisterChainInstruction(signerPk, chain as Chain));
  }

  if (registeredChainInfo === null ||
      registeredChainInfo.maxGasDropoffEth !== Number(peer.maxGasDropoffEth) ||
      registeredChainInfo.basePriceUsd !== Number(peer.basePriceUsd)) {
    instructions.push(await quoter.createUpdateChainParamsInstruction(signerPk, chain as Chain, Number(peer.maxGasDropoffEth), Number(peer.basePriceUsd)));
  }

  if (registeredChainInfo === null ||
      registeredChainInfo.nativePriceUsd !== Number(peer.nativePriceUsd) ||
      registeredChainInfo.gasPriceGwei !== Number(peer.gasPriceGwei)) {
    instructions.push(await quoter.createUpdateChainPricesInstruction(signerPk, chain as Chain, Number(peer.nativePriceUsd), Number(peer.gasPriceGwei)));
  }

  return ledgerSignAndSend(instructions, []);
}

run();
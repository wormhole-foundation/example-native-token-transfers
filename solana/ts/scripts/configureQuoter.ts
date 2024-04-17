import { Chain, isChain } from "@wormhole-foundation/sdk-base";
import { NttQuoter } from "../sdk";
import { PublicKey, TransactionInstruction } from "@solana/web3.js";

import { connection, getSigner, getEnv, peerQuotes, PeerQuotes } from "./env";
import { ledgerSignAndSend } from "./helpers";
import { inspect } from 'util';

interface QuoterConfig {
  // Fee recipient address encoded in base58.
  feeRecipient: string;
  // Assistant address encoded in base58. This account is able to update prices in the contract.
  assistant: string;
  // NTT quoter address encoded in base58.
  nttQuoterProgramId: string;
  // The price of SOL in USD in 10e6 decimals
  solPriceUsd: number;
}

const config: QuoterConfig = {
  assistant: getEnv("SOLANA_QUOTER_ASSISTANT"),
  feeRecipient: getEnv("SOLANA_QUOTER_FEE_RECIPIENT"),
  nttQuoterProgramId: getEnv("SOLANA_QUOTER_PROGRAM_ID"),
  solPriceUsd: Number(getEnv("SOL_PRICE_USD")),
};

async function run() {
  const signer = await getSigner();
  const signerPk = new PublicKey(await signer.getAddress());

  const feeRecipient = new PublicKey(config.feeRecipient);
  const assistant = new PublicKey(config.assistant);

  const quoter = new NttQuoter(connection, config.nttQuoterProgramId);

  let instanceState = await quoter.tryGetInstance();

  if (instanceState === null) {
    throw new Error("Can't configure a quoter un-initialized.");
  }

  const configurationInstructions: TransactionInstruction[] = [];

  if (!instanceState.feeRecipient.equals(feeRecipient)) {
    const feeRecipientInstruction = await quoter.createSetFeeRecipientInstruction(instanceState, feeRecipient);
    configurationInstructions.push(feeRecipientInstruction);
    console.log("Updating fee recipient to: ", config.feeRecipient);
  }

  if (!instanceState.assistant.equals(assistant)) {
    const assistantInstruction = await quoter.createSetAssistantInstruction(instanceState, assistant);
    configurationInstructions.push(assistantInstruction);
    console.log("Updating assistant to: ", config.assistant);
  }

  if (instanceState.solPriceUsd !== config.solPriceUsd) {
    const solPriceInstruction = await quoter.createUpdateSolPriceInstruction(signerPk, config.solPriceUsd);
    configurationInstructions.push(solPriceInstruction);
    console.log("Updating sol price to: ", config.solPriceUsd);
  }

  // add any other global configs here...

  try {
    if (configurationInstructions.length){
      const signature = await ledgerSignAndSend(configurationInstructions, []);
      console.log("Global config success. Tx=", signature);
    }
  } catch (error) {
    console.error("Failed to configure quoter contract:", error);
    return;
  }

  for (const [chain, peer] of Object.entries(peerQuotes)) {
    if (!isChain(chain)) {
      throw new Error(`Invalid chain name: ${chain}`);
    }

    try {
      console.log("Configuring peer chain: ", chain);
      await configurePeer(quoter, chain as Chain, peer, signerPk);
    } catch (error) {
      console.error(`Failed to configure ${chain} peer. Error: `, error);
    }
  }
}

async function configurePeer(quoter: NttQuoter, chain: Chain, peer: PeerQuotes, signerPk: PublicKey) {
  const instructions: TransactionInstruction[] = [];
  let registeredChainInfo = await quoter.tryGetRegisteredChain(chain as Chain);
  // console.log("registered info", inspect(registeredChainInfo));
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

  if (instructions.length === 0) {
    console.log("No updates needed for chain: ", chain);
    return;
  }
  
  return ledgerSignAndSend(instructions, []);
}

run();
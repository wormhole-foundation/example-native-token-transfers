import { Chain } from "@wormhole-foundation/sdk-base";
import { NttQuoter } from "../sdk";
import { Connection, Keypair, PublicKey, Signer, Transaction, TransactionInstruction, sendAndConfirmTransaction } from "@solana/web3.js";

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
  prices: Partial<Record<Chain, Quotes>>;
  /**
   * RPC URL for Solana.
   */
  rpcUrl: string;
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

async function sendTransaction(instructions: TransactionInstruction[], provider: Connection, signers: Signer[]) {
  const tx = new Transaction();
  tx.add(...instructions);
  await sendAndConfirmTransaction(provider, tx, signers, {maxRetries: 10});
}

async function run() {
  const config = {} as Config;
  const rpcUrl = config.rpcUrl;
  const feeRecipient = new PublicKey(config.feeRecipient);
  const assistant = new PublicKey(config.assistant);
  const signer = Keypair.fromSecretKey(Buffer.from("some key passed in by arg"));

  const provider = new Connection(rpcUrl, "confirmed");
  const quoter = new NttQuoter(provider, config.nttQuoterProgramId);

  // TODO: many of these instructions can probably be put together in a single transaction though probably not all of them.
  let instanceState = await quoter.tryGetInstance();
  if (instanceState === null) {
    const initInstruction = await quoter.createInitializeInstruction(feeRecipient);
    await sendTransaction([initInstruction], provider, [signer]);
    instanceState = (await quoter.tryGetInstance());
    if (instanceState === null) throw new Error(`Quoter instance account is empty.
- Maybe the initialization transaction rolled off the blockchain.
- Maybe the account query was answered by a node that is not synchronized`);
  } else if (!instanceState.feeRecipient.equals(feeRecipient)) {
    const feeRecipientInstruction = await quoter.createSetFeeRecipientInstruction(instanceState, new PublicKey(config.feeRecipient));
    await sendTransaction([feeRecipientInstruction], provider, [signer]);
  }

  if (!instanceState.assistant.equals(assistant)) {
    const assistantInstruction = await quoter.createSetAssistantInstruction(instanceState, new PublicKey(config.assistant));
    await sendTransaction([assistantInstruction], provider, [signer]);
  }

  for (const [chain, peer] of Object.entries(config.prices)) {
    const instructions: TransactionInstruction[] = [];
    let registeredChainInfo = await quoter.tryGetRegisteredChain(chain as Chain);
    if (registeredChainInfo === null) {
      instructions.push(await quoter.createRegisterChainInstruction(signer.publicKey, chain as Chain));
    }

    if (registeredChainInfo === null ||
        registeredChainInfo.maxGasDropoffEth !== Number(peer.maxGasDropoffEth) ||
        registeredChainInfo.basePriceUsd !== Number(peer.basePriceUsd)) {
      instructions.push(await quoter.createUpdateChainParamsInstruction(signer.publicKey, chain as Chain, Number(peer.maxGasDropoffEth), Number(peer.basePriceUsd)));
    }

    if (registeredChainInfo === null ||
        registeredChainInfo.nativePriceUsd !== Number(peer.nativePriceUsd) ||
        registeredChainInfo.gasPriceGwei !== Number(peer.gasPriceGwei)) {
      instructions.push(await quoter.createUpdateChainPricesInstruction(signer.publicKey, chain as Chain, Number(peer.nativePriceUsd), Number(peer.gasPriceGwei)));
    }

    console.log(`Sending price updates for chain ${chain}`);
    // TODO: can we actually string these three instructions together or is it too much?
    await sendTransaction(instructions, provider, [signer]);
  }
}

run();
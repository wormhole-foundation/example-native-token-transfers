import { TransactionSignatureAndResponse } from "@certusone/wormhole-sdk/lib/cjs/solana";
import {
  Connection,
  RpcResponseAndContext,
  SignatureStatus,
} from "@solana/web3.js";
import fs from "fs";
import { Config } from ".";

export type OutputMetrics = {
  envName: string;
  solanaRpc: string;
  testWalletLocation: string;
  shouldAirdrop: boolean;
  numberOfKeypairs: number;
  numberOfTotalTransactions: number;

  // metrics
  totalTransactions: number;
  totalTransactionsSucceeded: number;
  totalTransactionsFailed: number;
  lastValidBlockHeight: number;
  successPercentage: number;
  transactionsPerSecondWalltime: number;
};

export async function createOutputMetrics(
  config: Config,
  results: RpcResponseAndContext<SignatureStatus | null>[],
  lastValidBlockHeight: number,
  wallTimeStart: number,
  wallTimeEnd: number
): Promise<OutputMetrics> {
  const totalTransactions = results.length;
  const totalTransactionsFailed = results.filter(
    (result) => result.value === null || result.value?.err
  ).length;
  const totalTransactionsSucceeded =
    totalTransactions - totalTransactionsFailed;
  const successPercentage =
    (totalTransactionsSucceeded / totalTransactions) * 100;
  console.log("Last valid block height: ", lastValidBlockHeight);
  console.log("Wall time start: ", wallTimeStart);
  console.log("Wall time end: ", wallTimeEnd);
  console.log("Wall time duration: ", wallTimeEnd - wallTimeStart);

  const transactionsPerSecondWalltime =
    (totalTransactionsSucceeded * 1000) / (wallTimeEnd - wallTimeStart);

  //TODO slotmap

  console.log("Metrics: ");
  console.log("Total transactions: ", totalTransactions);
  console.log("Total transactions succeeded: ", totalTransactionsSucceeded);
  console.log("Total transactions failed: ", totalTransactionsFailed);
  console.log("Success percentage: ", successPercentage);
  console.log(
    "Transactions per second (walltime): ",
    transactionsPerSecondWalltime
  );

  console.log("debug");
  results.forEach((result) => {
    console.log(JSON.stringify(result, null, 2));
  });

  return {
    ...config,
    totalTransactions,
    totalTransactionsSucceeded,
    totalTransactionsFailed,
    lastValidBlockHeight,
    successPercentage,
    transactionsPerSecondWalltime,
  };
}

export function writeOutputMetrics(metrics: OutputMetrics) {
  //first mkdir sync on the output directory
  if (!fs.existsSync("./ts/metrics/output/")) {
    fs.mkdirSync("./ts/metrics/output/");
  }
  fs.writeFileSync(
    `./ts/metrics/output/${Date.now()}.json`,
    JSON.stringify(metrics, null, 2)
  );
}

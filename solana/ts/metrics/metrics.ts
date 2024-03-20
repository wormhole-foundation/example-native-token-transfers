import { TransactionSignatureAndResponse } from "@certusone/wormhole-sdk/lib/cjs/solana";
import {
  Connection,
  RpcResponseAndContext,
  SignatureStatus,
} from "@solana/web3.js";
import fs from "fs";
import { Config } from ".";
import { numberMaxSize } from "@wormhole-foundation/sdk-base/dist/cjs/utils/layout/layout";

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
  transactionsPerSecond: number;
};

export async function createOutputMetrics(
  config: Config,
  results: RpcResponseAndContext<SignatureStatus | null>[],
  lastValidBlockHeight: number,
  wallTimeStart: number,
  wallTimeEnd: number,
  connection: Connection
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

  const slotMap = new Map<number, number>();
  results.forEach((result) => {
    if (result.value?.slot) {
      if (slotMap.get(result.value.slot)! > 1) {
        slotMap.set(result.value.slot, slotMap.get(result.value.slot)! + 1);
      } else {
        slotMap.set(result.value.slot, 1);
      }
    }
  });

  let lowInclusionSlot = Math.min(...slotMap.keys());
  let highInclusionSlot = Math.max(...slotMap.keys());
  let delta = 1;

  console.log("Low inclusion slot: ", lowInclusionSlot);
  console.log("High inclusion slot: ", highInclusionSlot);

  if (lowInclusionSlot && highInclusionSlot) {
    let timestampLowInclusionSlot = (
      await connection.getBlock(lowInclusionSlot)
    )?.blockTime;
    let timestampHighInclusionSlot = (
      await connection.getBlock(highInclusionSlot)
    )?.blockTime;

    if (!timestampLowInclusionSlot || !timestampHighInclusionSlot) {
      timestampHighInclusionSlot = 1;
      timestampLowInclusionSlot = 0;
    }

    delta = timestampHighInclusionSlot - timestampLowInclusionSlot;
  }

  console.log("Metrics: ");
  console.log("Total transactions: ", totalTransactions);
  console.log("Total transactions succeeded: ", totalTransactionsSucceeded);
  console.log("Total transactions failed: ", totalTransactionsFailed);
  console.log("Success percentage: ", successPercentage);

  const transactionsPerSecond = (totalTransactionsSucceeded * 1000) / delta;

  console.log("Transactions per second (walltime): ", transactionsPerSecond);

  // console.log("debug");
  // results.forEach((result) => {
  //   console.log(JSON.stringify(result, null, 2));
  // });

  return {
    ...config,
    totalTransactions,
    totalTransactionsSucceeded,
    totalTransactionsFailed,
    lastValidBlockHeight,
    successPercentage,
    transactionsPerSecond,
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

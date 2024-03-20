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
  slotMap: Map<number, number>;
  slotTimestamps: Map<number, number>;
  avgPerSlot: number;
  maxPerSlot: number;
};

export async function createOutputMetrics(
  config: Config,
  results: RpcResponseAndContext<SignatureStatus | null>[],
  lastValidBlockHeight: number,
  startTime: number,
  slotTimestamps: Map<number, number>
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
  const slotMap = createSlotMap(results);

  let lowInclusionSlot = Math.min(...slotMap.keys());
  let highInclusionSlot = Math.max(...slotMap.keys());
  let delta = 1;

  console.log("Low inclusion slot: ", lowInclusionSlot);
  console.log("High inclusion slot: ", highInclusionSlot);
  console.log("Time start: " + startTime);

  let timeEnd = 0;
  let timeStart = startTime;
  if (slotTimestamps.has(lowInclusionSlot)) {
    console.log(
      "low inclusion slot timestamp: ",
      slotTimestamps.get(lowInclusionSlot)
    );
    timeStart = slotTimestamps.get(lowInclusionSlot)!;
  } else {
    console.log(
      "ERROR : low inclusion slot timestamp not found, delta will use broadcast start time"
    );
  }

  if (slotTimestamps.has(highInclusionSlot)) {
    console.log(
      "High inclusion slot timestamp: ",
      slotTimestamps.get(highInclusionSlot)
    );
    timeEnd = slotTimestamps.get(highInclusionSlot)!;
  } else {
    console.log(
      "ERROR : high inclusion slot timestamp not found, delta will be incorrect"
    );
  }

  delta = timeEnd - timeStart;

  console.log("Metrics: ");
  console.log("Total transactions: ", totalTransactions);
  console.log("Total transactions succeeded: ", totalTransactionsSucceeded);
  console.log("Total transactions failed: ", totalTransactionsFailed);
  console.log("Success percentage: ", successPercentage);
  console.log("Inclusion timestamp delta: ", delta);

  const transactionsPerSecond = totalTransactionsSucceeded / delta;

  console.log("Transactions per second (walltime): ", transactionsPerSecond);

  const avgPerSlot =
    totalTransactionsSucceeded / (highInclusionSlot - lowInclusionSlot + 1);
  console.log("Average per slot: ", avgPerSlot);
  const maxPerSlot = Math.max(...slotMap.values());
  console.log("Max per slot: ", maxPerSlot);

  return {
    ...config,
    totalTransactions,
    totalTransactionsSucceeded,
    totalTransactionsFailed,
    lastValidBlockHeight,
    successPercentage,
    transactionsPerSecond,
    slotMap,
    slotTimestamps,
    avgPerSlot,
    maxPerSlot,
  };
}

function createSlotMap(
  results: RpcResponseAndContext<SignatureStatus | null>[]
): Map<number, number> {
  const slotMap = new Map<number, number>();
  results.forEach((result) => {
    if (
      result.value?.slot &&
      isFinite(result.value.slot) &&
      result.value.slot > 0
    ) {
      if (slotMap.get(result.value.slot)! > 0) {
        slotMap.set(result.value.slot, slotMap.get(result.value.slot)! + 1);
      } else {
        slotMap.set(result.value.slot, 1);
      }
    }
  });
  return slotMap;
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

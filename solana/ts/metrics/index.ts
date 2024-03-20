import fs from "fs";
import {
  Keypair,
  Connection,
  Transaction,
  TransactionInstruction,
  SystemProgram,
  PublicKey,
  sendAndConfirmTransaction,
  BlockResponse,
} from "@solana/web3.js";
import { NTT } from "../sdk";
import nacl from "tweetnacl";
import {
  UnsignedNttTransfer,
  airdrop,
  bulkFetchTxSignatures,
  createInitializeTransaction,
  createUnsignedNttBridgeTestTransaction,
  initializeAllWallets,
  transactionBulkBroadcast,
} from "./helpers";
import {
  OutputMetrics,
  createOutputMetrics,
  writeOutputMetrics,
} from "./metrics";

export type Config = {
  envName: string;
  solanaRpc: string;
  testWalletLocation: string;
  nttId: string;
  wormholeId: string;
  shouldAirdrop: boolean;
  numberOfKeypairs: number;
  numberOfTotalTransactions: number;
  testTransferAmount: number;
};

const localhostConfig: Config = {
  envName: "local",
  solanaRpc: "http://localhost:8899",
  testWalletLocation: "./keys/test.json",
  nttId: "nttiK1SepaQt6sZ4WGW5whvc9tEnGXGxuKeptcQPCcS",
  wormholeId: "worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth",
  shouldAirdrop: true,
  numberOfKeypairs: 50,
  numberOfTotalTransactions: 500,
  testTransferAmount: 100,
};

const config = localhostConfig;

async function run() {
  console.log("Starting Solana metrics test");
  console.log("Config: ", config);

  const primaryTestWallet = Keypair.fromSecretKey(
    Uint8Array.from(
      JSON.parse(fs.readFileSync(config.testWalletLocation).toString())
    )
  );
  console.log("Primary test wallet: ", primaryTestWallet.publicKey.toBase58());

  const connection = new Connection(config.solanaRpc);
  if (config.shouldAirdrop) {
    console.log("Airdropping to primary wallet");
    await airdrop(config.testWalletLocation, connection);
    console.log("Airdrop complete");
  } else {
    console.log("Skipping airdrop");
  }

  const ntt = new NTT(connection, {
    nttId: config.nttId as any,
    wormholeId: config.wormholeId as any,
  });
  const mintAccount = await ntt.mintAccountAddress();

  // generate keypairs and create initializing transactions
  console.log("Generating " + config.numberOfKeypairs + " keypairs");
  const keypairs: Keypair[] = [];
  const initializeRecentBlockhash = await connection.getRecentBlockhash();
  for (let i = 0; i < config.numberOfKeypairs; i++) {
    keypairs.push(Keypair.generate());
  }
  console.log("Generated keypairs");
  console.log("Initializing all test wallets for the generated keypairs");
  const initializeSuccess = await initializeAllWallets(
    primaryTestWallet,
    keypairs,
    config.testTransferAmount,
    Math.ceil(config.numberOfTotalTransactions / config.numberOfKeypairs),
    mintAccount,
    initializeRecentBlockhash.blockhash,
    connection
  );

  if (!initializeSuccess) {
    throw new Error("Failed to initialize keypairs");
  }

  console.log("Initialized all test wallets");

  //create test transactions
  console.log("Creating test transactions");

  //The test transactions require network to create,
  //so we want to avoid signing them until the last moment to avoid latency
  const testTransactionsUnsigned: UnsignedNttTransfer[] = [];
  for (let i = 0; i < config.numberOfTotalTransactions; i++) {
    testTransactionsUnsigned.push(
      await createUnsignedNttBridgeTestTransaction(
        connection,
        keypairs[i % keypairs.length],
        config.nttId,
        config.wormholeId,
        mintAccount,
        config.testTransferAmount
      )
    );
  }
  console.log("Finished creating unsigned transactions");

  //pull the current timestamp of the slot at the start of this test
  const recentBlockhash = await connection.getLatestBlockhashAndContext();
  const lastValidHeight = recentBlockhash.value.lastValidBlockHeight;
  const startBlock = await connection.getBlock(
    recentBlockhash.value.lastValidBlockHeight - 300
  ); //weird
  if (
    !startBlock ||
    startBlock.blockTime === null ||
    startBlock.blockTime === undefined
  ) {
    throw new Error("Failed to fetch start block time");
  }
  const timeStart = startBlock.blockTime;
  console.log("Start time: ", timeStart);
  console.log("Last valid height: ", lastValidHeight);

  //sign all the transactions really quickly
  console.log("Signing all test transactions");
  const signedTestTransactions: Transaction[] = [];
  for (let i = 0; i < config.numberOfTotalTransactions; i++) {
    const unsignedTransaction = testTransactionsUnsigned[i];
    unsignedTransaction.unsignedTransaction.recentBlockhash =
      recentBlockhash.value.blockhash;
    unsignedTransaction.unsignedTransaction.sign(
      keypairs[i % keypairs.length],
      unsignedTransaction.outboxKey
    );
    signedTestTransactions.push(unsignedTransaction.unsignedTransaction);
  }
  console.log("Finished signing all test transactions");

  //broadcast the transactions
  console.log("Broadcasting test transactions");

  //NOTE: intentionally not awaiting this, as we want to immediately start pulling blocks.
  const transactionSignaturesPromise = Promise.all(
    transactionBulkBroadcast(signedTestTransactions, connection)
  ).then((results) => {
    console.log("Broadcasted all test transactions!!!!");
    console.log("!!!!!!");
    console.log("!!!!!!");
    return results;
  });

  let done = false;
  const slotTimestamps = new Map<number, number>();
  while (!done) {
    //pull the current slotheight
    const currentSlot = await connection.getSlot();
    let currentBlock: BlockResponse | null = null;

    try {
      currentBlock = await connection.getBlock(currentSlot);
    } catch (error) {
      console.log("Error fetching block: ", error);
    }
    //RPCs aggressively clean up old slots, so we need to keep track of the timestamps here
    //because they wont be available during metrics processing.
    if (
      currentBlock &&
      currentBlock.blockTime !== null &&
      currentBlock.blockTime !== undefined
    ) {
      slotTimestamps.set(currentSlot, currentBlock.blockTime);
    }

    //if the currentSlot is greater than the lastValidHeight, then we are done
    if (currentSlot > lastValidHeight) {
      done = true;
    } else {
      //wait a bit
      console.log(
        `Waiting for ${lastValidHeight - currentSlot} slots before ending`
      );
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  const wallTimeEnd = Date.now();

  console.log("Passed endtime of test.");
  //Pull all the transactions to see what percentage were included

  console.log("waiting 3 seconds for inclusions to settle");
  await new Promise((resolve) => setTimeout(resolve, 3000));

  //Here is the part where we can't wait for the broadcast anymore
  const transactionSignatureResults = await transactionSignaturesPromise;

  console.log("Fetching transaction signatures of all test transactions.");
  const transactionResults = await Promise.all(
    bulkFetchTxSignatures(connection, transactionSignatureResults)
  );
  console.log("Fetched transaction signatures of all test transactions.");

  console.log("Creating output metrics");
  const metrics = await createOutputMetrics(
    config,
    transactionResults,
    lastValidHeight,
    timeStart,
    slotTimestamps
  );

  console.log("Writing output metrics");
  writeOutputMetrics(metrics);

  console.log("Done! - Exiting test.");
}

//wait for run to end
run()
  .then(() => {
    console.log("done");
  })
  .catch((error) => {
    console.error(error);
  });

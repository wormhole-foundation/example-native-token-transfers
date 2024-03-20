import fs from "fs";
import {
  Keypair,
  Connection,
  Transaction,
  TransactionInstruction,
  SystemProgram,
  PublicKey,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import { NTT } from "../sdk";
import nacl from "tweetnacl";
import {
  airdrop,
  bulkFetchTxSignatures,
  createInitializeTransaction,
  createNttBridgeTestTransaction,
  transactionBulkBroadcast,
} from "./helpers";
import {
  OutputMetrics,
  createOutputMetrics,
  writeOutputMetrics,
} from "./metrics";

const SLOT_EXPIRATION_PERIOD = 300;

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
  numberOfKeypairs: 250,
  numberOfTotalTransactions: 750,
  testTransferAmount: 1000,
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
  const initializingTransactions: Transaction[] = [];
  const initializeRecentBlockhash = await connection.getRecentBlockhash();
  for (let i = 0; i < config.numberOfKeypairs; i++) {
    keypairs.push(Keypair.generate());
    initializingTransactions.push(
      createInitializeTransaction(
        primaryTestWallet,
        keypairs[i],
        mintAccount,
        initializeRecentBlockhash.blockhash,
        config.testTransferAmount
      )
    );
  }
  console.log("Generated keypairs and initializing transactions");

  //TODO handle if some of the initializing transactions fail
  //Bulk broadcast the initializing transactions
  console.log("Broadcasting initializing transactions");
  const initializingSignatures = await Promise.all(
    transactionBulkBroadcast(initializingTransactions, connection)
  );

  //wait 3 seconds for inclusion to settle out
  await new Promise((resolve) => setTimeout(resolve, 30000));

  console.log("Finished broadcasting initializing transactions");
  console.log("Pulling results of initializing transactions");
  const initializingResults = await Promise.all(
    bulkFetchTxSignatures(connection, initializingSignatures)
  );
  console.log("Pulled results of initializing transactions");
  for (let i = 0; i < initializingResults.length; i++) {
    if (
      initializingResults[i].value === null ||
      initializingResults[i].value?.err
    ) {
      console.log("debug:");
      console.log(initializingSignatures[i]);
      console.log(JSON.stringify(initializingResults[i], null, 2));
      throw new Error("Failed to initialize keypair at index " + i);
    }
  }

  //create test transactions
  console.log("Creating test transactions");
  const recentBlockhash = await connection.getLatestBlockhashAndContext();

  const lastValidHeight = recentBlockhash.value.lastValidBlockHeight;

  const signedHeight = recentBlockhash.context.slot;
  console.log("Signed using blockhash for hestight : " + signedHeight);
  console.log("Last possible valid height : ", lastValidHeight);

  const testTransactions: Transaction[] = [];
  for (let i = 0; i < config.numberOfTotalTransactions; i++) {
    testTransactions.push(
      await createNttBridgeTestTransaction(
        connection,
        keypairs[i % keypairs.length],
        recentBlockhash.value.blockhash,
        config.nttId,
        config.wormholeId,
        mintAccount,
        config.testTransferAmount
      )
    );
  }
  console.log("Finished creating test transactions");

  //broadcast the transactions
  const wallTimeStart = Date.now();
  console.log("Broadcasting test transactions");
  const transactionSignatures = await Promise.all(
    transactionBulkBroadcast(testTransactions, connection)
  );
  console.log("Finished broadcasting test transactions");

  let done = false;
  while (!done) {
    //pull the current slotheight
    const currentSlot = await connection.getSlot();

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

  console.log("waiting 1 second for inclusions to settle");
  await new Promise((resolve) => setTimeout(resolve, 1000));

  console.log("Fetching transaction signatures of all test transactions.");
  const transactionResults = await Promise.all(
    bulkFetchTxSignatures(connection, transactionSignatures)
  );
  console.log("Fetched transaction signatures of all test transactions.");

  console.log("Creating output metrics");
  const metrics = await createOutputMetrics(
    config,
    transactionResults,
    lastValidHeight,
    wallTimeStart,
    wallTimeEnd,
    connection
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

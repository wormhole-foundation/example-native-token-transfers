import { inspect } from "util";
import {
  NttManager__factory,
} from "../contract-bindings";
import {
  loadOperatingChains,
  init,
  ChainInfo,
  getSigner,
  getContractAddress,
} from "./env";

const processName = "transferManagerOwnership";

init();
const chains = loadOperatingChains();

async function run() {
  console.log(`Start ${processName}!`);

  const results = await Promise.all(
    chains.map(async (chain) => transferOwnership(chain))
  );

  for (const result of results) {
    if ("error" in result) {
      console.error(
        `Error deploying for chain ${result.chainId}: ${inspect(result.error)}`
      );
      continue;
    }

    console.log(`Deployed succeded for chain ${result.chainId}`);
  }
}

async function transferOwnership(chain: ChainInfo) {
  const log = (...args: any[]) => console.log(`[${chain.chainId}]`, ...args);
  const signer = await getSigner(chain);

  const managerContractAddress = await getContractAddress("NttManagerProxies", chain.chainId);
  const governanceContractAddress = await getContractAddress("GeneralPurposeGovernances", chain.chainId);

  const managerContract = NttManager__factory.connect(
    managerContractAddress,
    signer
  );

  log(`Transferring ownership of manager ${managerContractAddress} to governance: ${governanceContractAddress}`);
  const transferTx = await managerContract.transferOwnership(governanceContractAddress);

  log(`sent tx: ${transferTx.hash}`)
  
  await transferTx.wait();

  log(`Ownership transferred`);
  
  return {
    chainId: chain.chainId,
  };
}

run().then(() => console.log("Done!"));


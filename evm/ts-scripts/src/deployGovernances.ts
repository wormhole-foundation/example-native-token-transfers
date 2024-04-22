import { inspect } from "util";
import {
  Governance__factory,
} from "../contract-bindings";
import {
  loadOperatingChains,
  init,
  ChainInfo,
  writeOutputFiles,
  Deployment,
  getSigner,
  getContractAddress,
} from "./env";

const processName = "deployGovernances";

init();
const chains = loadOperatingChains();

async function run() {
  console.log(`Start ${processName}!`);

  const output = {
    GeneralPurposeGovernances: [] as Deployment[],
  };

  const results = await Promise.all(
    chains.map(async (chain) => deployGovernance(chain))
  );

  for (const result of results) {
    if ("error" in result) {
      console.error(
        `Error deploying for chain ${result.chainId}: ${inspect(result.error)}`
      );
      continue;
    }

    console.log(`Deployed succeded for chain ${result.chainId}`);
    output.GeneralPurposeGovernances.push(result.governance);
  }

  writeOutputFiles(output, processName);
}

async function deployGovernance(chain: ChainInfo) {
  let governance: Deployment;
  const log = (...args: any[]) => console.log(`[${chain.chainId}]`, ...args);

  try {
    governance = await deployGovernanceImplementation(chain);
    log("Implementation deployed at ", governance.address);
  } catch (error) {
    return { chainId: chain.chainId, error };
  }

  return {
    chainId: chain.chainId,
    governance,
  };
}

run().then(() => console.log("Done!"));

async function deployGovernanceImplementation(
  chain: ChainInfo,
): Promise<Deployment> {
  const signer = await getSigner(chain);

  const coreContract = await getContractAddress("WormholeCoreContracts", chain.chainId);

  const governanceFactory = new Governance__factory(signer);
  const governance = await governanceFactory.deploy(
    coreContract,
    // overrides,
  );

  await governance.deployed();
  return { address: governance.address, chainId: chain.chainId };
}

import { inspect } from "util";
import { CONTRACTS, coalesceChainName } from "@certusone/wormhole-sdk";
import {
  ERC1967Proxy__factory,
  Governance__factory,
} from "../contract-bindings";
import {
  loadOperatingChains,
  init,
  ChainInfo,
  writeOutputFiles,
  Deployment,
  getSigner,
} from "./env";

const processName = "deployGovernances";

init();
const chains = loadOperatingChains();

async function run() {
  console.log(`Start ${processName}!`);

  const output = {
    GeneralPurposeGovernanceImplementations: [] as Deployment[],
    GeneralPurposeGovernanceProxies: [] as Deployment[],
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
    output.GeneralPurposeGovernanceImplementations.push(result.implementation);
    output.GeneralPurposeGovernanceProxies.push(result.proxy);
  }

  writeOutputFiles(output, processName);
}

async function deployGovernance(chain: ChainInfo) {
  let implementation: Deployment, proxy: Deployment;
  const log = (...args: any[]) => console.log(`[${chain.chainId}]`, ...args);

  try {
    implementation = await deployGovernanceImplementation(chain);
    log("Implementation deployed at ", implementation.address);
  } catch (error) {
    return { chainId: chain.chainId, error };
  }

  try {
    proxy = await deployGovernanceProxy(chain, implementation.address);
    log("Proxy deployed at ", proxy.address);
  } catch (error) {
    return { chainId: chain.chainId, error };
  }

  return {
    chainId: chain.chainId,
    implementation,
    proxy,
  };
}

run().then(() => console.log("Done!"));

async function deployGovernanceImplementation(
  chain: ChainInfo,
): Promise<Deployment> {
  const signer = await getSigner(chain);

  const coreContract = CONTRACTS.MAINNET[coalesceChainName(chain.chainId)].core;
  if (coreContract === undefined) {
    throw new Error(`Failed to find core contract for chain ${chain.chainId}`);
  }

  const governanceFactory = new Governance__factory(signer);
  const governance = await governanceFactory.deploy(
    coreContract,
    // overrides,
  );

  await governance.deployed();
  return { address: governance.address, chainId: chain.chainId };
}

async function deployGovernanceProxy(
  chain: ChainInfo,
  implementationAddress: string
): Promise<Deployment> {
  const signer = await getSigner(chain);

  const proxyFactory = new ERC1967Proxy__factory(signer);

  const proxy = await proxyFactory.deploy(implementationAddress, []);

  await proxy.deployed();
  return { address: proxy.address, chainId: chain.chainId };
}

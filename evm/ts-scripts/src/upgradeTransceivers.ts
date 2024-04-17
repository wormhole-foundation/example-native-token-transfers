import { inspect } from "util";
import { ethers } from "ethers";
import { ChainId } from "@certusone/wormhole-sdk";

import {
  WormholeTransceiver__factory,
} from "../contract-bindings";
import { WormholeTransceiverLibraryAddresses } from '../contract-bindings/factories/WormholeTransceiver__factory';
import {
  loadOperatingChains,
  init,
  ChainInfo,
  writeOutputFiles,
  Deployment,
  getSigner,
  loadScriptConfig,
  getContractAddress,
} from "./env";

const processName = "upgradeTransceivers";

interface TxResult {
  chainId: ChainId;
  tx: ethers.ContractTransaction;
  receipt: ethers.ContractReceipt;
}

type NttTransceiverConfig = {
  chainId: ChainId;
  consistencyLevel: number;
  gasLimit: number;
};

type NttTransceiverDependencies = {
  manager: string;
  wormhole: string;
  wormholeRelayer: string;
  specializedRelayer: string;
};

init();
const chains = loadOperatingChains();

// Warning: we assume that the script configuration file is correctly formed
const config: NttTransceiverConfig[] = loadScriptConfig("transceivers");

async function run() {
  console.log(`Start ${processName}!`);

  const output= {
    NttTransceiverImplementations: [] as Deployment[],
    TransceiverStructsLibs: [] as Deployment[],
  };

  const results = await Promise.all(
    chains.map(async (chain) => {
      const chainConfig = config.find((c) => c.chainId === chain.chainId);
      if (!chainConfig) {
        console.error(`No configuration found for chain ${chain.chainId}`);
        return { chainId: chain.chainId, error: "No configuration found" };
      }

      const chainContracts: NttTransceiverDependencies = await getChainContracts(chain.chainId);

      const result = await upgradeTransceiver(chain, chainConfig, chainContracts);
      return result;
    })
  );

  for (const result of results) {
    if ("error" in result) {
      console.error(
        `Error deploying for chain ${result.chainId}: ${inspect(
          result.error
        )}`
      );
      continue;
    }

    output.NttTransceiverImplementations.push(result.implementation);
    output.TransceiverStructsLibs.push(result.transceiverStructsLibs);
  }

  writeOutputFiles(output, processName);
}

async function upgradeTransceiver(chain: ChainInfo, config: NttTransceiverConfig, contracts: NttTransceiverDependencies) {
  const log = (...args) => console.log(`[${chain.chainId}]`, ...args);

  let implementation: Deployment, upgradeTx: TxResult, libraries: WormholeTransceiverLibraryAddresses;

  // TODO: we need to check whether we should redeploy this first
  // It just reuses the current deployed library as it is.
  const structsLibAddress = await getContractAddress("TransceiverStructsLibs", chain.chainId);
  libraries = {
    ["src/libraries/TransceiverStructs.sol:TransceiverStructs"]: structsLibAddress,
  };

  log("Deploying new implementation");
  try {
    implementation = await deployTransceiverImplementation(chain, config, contracts, libraries);
    log("Implementation deployed at ", implementation.address);
  } catch (error) {
    return { chainId: chain.chainId, error };
  }

  log("Executing upgrade on proxy");
  try {
    upgradeTx = await executeUpgradeTransceiver(chain, implementation.address);
    log("Upgrade executed successfully");
  } catch (error) {
    return { chainId: chain.chainId, error };
  }

  return {
    chainId: chain.chainId,
    implementation,
    transceiverStructsLibs: {
      chainId: chain.chainId,
      address: structsLibAddress,
    },
    upgradeTx,
  };
}

run().then(() => console.log("Done!"));

async function deployTransceiverImplementation(
  chain: ChainInfo,
  config: NttTransceiverConfig,
  contracts: NttTransceiverDependencies,
  libraries: WormholeTransceiverLibraryAddresses,
): Promise<Deployment> {
  const signer = await getSigner(chain);

  const transceiverFactory = new WormholeTransceiver__factory(libraries, signer);
  const transceiver = await transceiverFactory.deploy(
    contracts.manager,
    contracts.wormhole,
    contracts.wormholeRelayer,
    contracts.specializedRelayer,
    BigInt(config.consistencyLevel),
    BigInt(config.gasLimit),
  );

  await transceiver.deployed();
  return { address: transceiver.address, chainId: chain.chainId };
}

async function executeUpgradeTransceiver(
  chain: ChainInfo,
  implementationAddress: string
): Promise<TxResult> {
  const signer = await getSigner(chain);

  const proxyAddress = await getContractAddress("NttTransceiverProxies", chain.chainId);
  const proxy = WormholeTransceiver__factory.connect(proxyAddress, signer);

  // TODO: add overrides to facilitate customizing tx parameters per chain.
  const tx = await proxy.upgrade(implementationAddress);
  console.log(`Upgrade tx sent, hash: ${tx.hash}`);
  const receipt = await tx.wait();
  if (receipt.status !== 1) {
    throw new Error(`Failed to execute upgrade on chain ${chain.chainId}, tx hash: ${receipt.transactionHash}`);
  }

  return { tx, receipt, chainId: chain.chainId };
}

async function getChainContracts(chainId: ChainId): Promise<NttTransceiverDependencies> {
  const [wormhole, wormholeRelayer, specializedRelayer, manager] = await Promise.all([
    getContractAddress("WormholeCoreContracts", chainId),
    getContractAddress("WormholeRelayers", chainId),
    getContractAddress("SpecializedRelayers", chainId),
    getContractAddress("NttManagerProxies", chainId),
  ]);

  return { manager, wormhole, wormholeRelayer, specializedRelayer}
}

import { inspect } from "util";
import { ethers } from "ethers";
import { ChainId } from "@certusone/wormhole-sdk";

import {
  TransceiverStructs__factory,
  WormholeTransceiver__factory,
  ERC1967Proxy__factory
} from "../contract-bindings";
import { WormholeTransceiverLibraryAddresses,  } from '../contract-bindings/factories/WormholeTransceiver__factory';
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

const processName = "deployTransceivers";

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

  const output: any = {
    NttTransceiverImplementations: [],
    NttTransceiverProxies: [],
  };

  const results = await Promise.all(
    chains.map(async (chain) => {
      const chainConfig = config.find((c) => c.chainId === chain.chainId);
      if (!chainConfig) {
        console.error(`No configuration found for chain ${chain.chainId}`);
        return { chainId: chain.chainId, error: "No configuration found" };
      }

      const chainContracts: NttTransceiverDependencies = await getChainContracts(chain.chainId);

      const result = await deployTransceiver(chain, chainConfig, chainContracts);
      return result;
    })
  );

  for (const result of results) {
    if (result.error) {
      console.error(
        `Error deploying for chain ${result.chainId}: ${inspect(
          result.error
        )}`
      );
      continue;
    }

    output.NttTransceiverImplementations.push(result.implementation);
    output.NttTransceiverProxies.push(result.proxy);
  }

  writeOutputFiles(output, processName);
}

async function deployTransceiver(chain: ChainInfo, config: NttTransceiverConfig, contracts: NttTransceiverDependencies) {
  const log = (...args) => console.log(`[${chain.chainId}]`, ...args);

  let implementation, proxy, libraries;

  const structsLibAddress = await getContractAddress("TransceiverStructsLibs", chain.chainId);
  libraries = {
    ["src/libraries/TransceiverStructs.sol:TransceiverStructs"]: structsLibAddress,
  };

  log("Deploying implementation");
  try {
    implementation = await deployTransceiverImplementation(chain, config, contracts, libraries);
    log("Implementation deployed to ", implementation.address);
  } catch (error) {
    return { chainId: chain.chainId, error };
  }

  log("Deploying proxy");
  try {
    proxy = await deployTransceiverProxy(chain, implementation.address);
    log("Proxy deployed to ", proxy.address);
  } catch (error) {
    return { chainId: chain.chainId, error };
  }

  return {
    chainId: chain.chainId,
    implementation,
    libraries,
    proxy,
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

  return await transceiver.deployed().then((result) => {
    return { address: result.address, chainId: chain.chainId };
  });
}

async function deployTransceiverProxy(
  chain: ChainInfo,
  implementationAddress: string
): Promise<Deployment> {
  const signer = await getSigner(chain);

  const proxyFactory = new ERC1967Proxy__factory(signer);

  const abi = ["function initialize()"];
  const iface = new ethers.utils.Interface(abi);
  const encodedCall = iface.encodeFunctionData("initialize");

  const proxy = await proxyFactory.deploy(implementationAddress, encodedCall);

  return await proxy.deployed().then((result) => {
    return { address: result.address, chainId: chain.chainId };
  });
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

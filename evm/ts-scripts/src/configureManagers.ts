import { inspect } from "util";
import { ChainId } from "@certusone/wormhole-sdk";
import {
  NttManager__factory,
} from "../contract-bindings";
import {
  loadOperatingChains,
  init,
  ChainInfo,
  getSigner,
  getChainConfig,
  getContractAddress,
} from "./env";

const processName = "configureManagers";

type ManagerConfig = {
  chainId: ChainId;
  threshold: number;
  outboundLimit: string;
};

init();
const chains = loadOperatingChains();

// Warning: we assume that the script configuration file is correctly formed
async function run() {
  console.log(`Start ${processName}!`);

  const results = await Promise.all(
    chains.map(async (chain) => {
      let config, transceiverAddress;

      try {
        config = getChainConfig<ManagerConfig>(processName, chain);
      } catch (error) {
        return { chainId: chain.chainId, error: "No configuration found" };
      }

      try {
        transceiverAddress = await getContractAddress("NttTransceiverProxies", chain.chainId);
      } catch (error) {
        return { chainId: chain.chainId, error: "No transceiver contract address found" };
      }

      const result = await configureManager(chain, transceiverAddress, config);
      return result;
    })
  );

  for (const result of results) {
    if (("error" in result)) {
      console.error(
        `Error configuring contract for chain ${result.chainId}: ${inspect(
          result.error
        )}`
      );
      continue;
    }

    console.log(`Configuration succeded for chain ${result.chainId}`);
  }
}

async function configureManager(chain: ChainInfo, transceiverAddress: string, config: ManagerConfig) {
  const log = (...args: any[]) => console.log(`[${chain.chainId}]`, ...args);

  const contract = await getManagerContract(chain);
  console.log("setting transceiver", transceiverAddress);
  await contract.setTransceiver(transceiverAddress);
  log(`transceiver address set to: ${transceiverAddress}`);
  console.log("config", config);
  await contract.setOutboundLimit(config.outboundLimit);
  log(`outboundLimit set to: ${config.outboundLimit}`);

  await contract.setThreshold(config.threshold);
  log(`Threshold configured to: ${config.threshold}`);

  return { chainId: chain.chainId };
}

async function getManagerContract(chain: ChainInfo) {
  const signer = await getSigner(chain);
  const managerAddress = await getContractAddress("NttManagerProxies", chain.chainId);
  return NttManager__factory.connect(managerAddress, signer);
}

run().then(() => console.log("Done!"));

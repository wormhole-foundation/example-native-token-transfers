import { inspect } from "util";
import { ChainId, CHAIN_ID_SOLANA, tryNativeToHexString } from "@certusone/wormhole-sdk";
import { utils } from "ethers";
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
  loadScriptConfig,
} from "./env";

const processName = "updatePeerAddresses";

type PeerConfig = {
  chainId: ChainId;
  decimals: number;
  managerAddress?: string;
};

init();
const chains = loadOperatingChains();
async function run() {
  // Warning: we assume that the script configuration file is correctly formed
  const config = await loadScriptConfig("peers") as PeerConfig[];
  console.log(`Start ${processName}!`);

  const results = await Promise.all(
    chains.map(async chain => {
      try {
        await registerPeers(chain, config);
      } catch (error) {
        return { chainId: chain.chainId, error };
      }
      
      return { chainId: chain.chainId };
    })
  )

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

async function registerPeers(chain: ChainInfo, peers: PeerConfig[]) {
  const log = (...args: any[]) => console.log(`[${chain.chainId}]`, ...args);

  const contract = await getManagerContract(chain);

  for (const peer of peers) {
    if (peer.chainId === chain.chainId) continue;
    
    const config = await getChainConfig<PeerConfig>(processName, peer.chainId);

    if (!config.decimals) return { chainId: chain.chainId, error: "No 'decimals' configuration found" };

    const peerAddress = await getNormalizedPeerAddress(peer, chain);

    if (!peerAddress) return { chainId: chain.chainId, error: "No 'managerAddress' found" };

    await contract.setPeer(peer.chainId, Buffer.from(peerAddress, "hex"), config.decimals);
    log(`Registered peer for chain ${peer.chainId} at ${peerAddress}.`);
  }

  return { chainId: chain.chainId };
}

async function getManagerContract(chain: ChainInfo) {
  const signer = await getSigner(chain);
  const managerAddress = await getContractAddress("NttManagerProxies", chain.chainId);
  return NttManager__factory.connect(managerAddress, signer);
}

async function getNormalizedPeerAddress(peer: PeerConfig, chain: ChainInfo) {
  const peerAddress = await getPeerAddress(peer, chain);
  if (!peerAddress) return;
  return tryNativeToHexString(peerAddress, peer.chainId);
}

async function getPeerAddress(peer: PeerConfig, chain: ChainInfo) {
  return peer.managerAddress ?? await getContractAddress("NttManagerProxies", peer.chainId);
}

run().then(() => console.log("Done!"));

import { inspect } from "util";
import { ChainId, tryNativeToHexString } from "@certusone/wormhole-sdk";
import {
  NttManager__factory,
  WormholeTransceiver__factory,
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
import { BigNumber } from "ethers";

const processName = "updatePeerAddresses";

type PeerConfig = {
  chainId: ChainId;
  decimals: number;
  inboundLimit: string;
  isWormholeRelayingEnabled: boolean;
  isWormholeEvmChain: boolean;
  isSpecialRelayingEnabled: boolean;

  managerAddress?: string;
  transceiverAddress?: string;
};

init();
const chains = loadOperatingChains();
async function run() {
  // Warning: we assume that the script configuration file is correctly formed
  const config = (await loadScriptConfig("peers")) as PeerConfig[];
  console.log(`Start ${processName}!`);

  const results = await Promise.all(
    chains.map(async (chain) => {
      let result: { chainId: ChainId; peerUpdateTxs: string[]; error?: unknown; };
      try {
        result = await registerPeers(chain, config);
      } catch (error: unknown) {
        return { chainId: chain.chainId, peerUpdateTxs: [] as string[], error };
      }

      return result;
    })
  );

  for (const result of results) {
    if ("error" in result) {
      console.error(
        `Error configuring contract for chain ${result.chainId}: ${inspect(
          result.error
        )}`
      );
      continue;
    }

    console.log(`NttManager set peer txs for chain ${result.chainId}: \n  ${result.peerUpdateTxs.join("\n  ")}`);
  }
}

async function registerPeers(chain: ChainInfo, peers: PeerConfig[]): Promise<{
  chainId: ChainId;
  peerUpdateTxs: string[]
  error?: unknown;
}> {
  const log = (...args: any[]) => console.log(`[${chain.chainId}]`, ...args);

  const managerContract = await getManagerContract(chain);
  const transceiverContract = await getTransceiverContract(chain);

  const peerUpdateTxs: string[] = [];
  for (const peer of peers) {
    if (peer.chainId === chain.chainId) continue;

    const config = await getChainConfig<PeerConfig>(processName, peer.chainId);

    if (!config.decimals)
      return {
        chainId: chain.chainId,
        peerUpdateTxs,
        error: "No 'decimals' configuration found",
      };

    const peerCurrentConfig = await managerContract.getPeer(peer.chainId);
    const desiredPeerAddress = await getNormalizedPeerManagerAddress(
      peer,
      chain
    );

    if (!desiredPeerAddress)
      return { chainId: chain.chainId, peerUpdateTxs, error: "No 'managerAddress' found" };

    if (
      peerCurrentConfig.peerAddress !== desiredPeerAddress ||
      peerCurrentConfig.tokenDecimals !== config.decimals
    ) {
      try {
        const tx = await managerContract.setPeer(
          peer.chainId,
          Buffer.from(desiredPeerAddress, "hex"),
          config.decimals,
          BigNumber.from(config.inboundLimit),
        );
        peerUpdateTxs.push(tx.hash);
        log(
          `Registered manager peer for chain ${peer.chainId} at ${desiredPeerAddress}. Tx hash ${tx.hash}`
        );
        await tx.wait();
      }
      catch (error) {
        log(`Error registering manager peer for chain ${peer.chainId}: ${error}`);
      }

    } else {
      log(
        `Manager peer for chain ${peer.chainId} already registered at ${peerCurrentConfig.peerAddress}.`
      );
    }

    const currentTransceiverAddr = await transceiverContract.getWormholePeer(
      peer.chainId
    );

    const desiredTransceiverAddr = await getNormalizedPeerTransceiverAddress(
      peer,
      chain
    );

    if (!desiredTransceiverAddr)
      return {
        chainId: chain.chainId,
        peerUpdateTxs,
        error: "No 'transceiverAddress' found",
      };

    if (desiredTransceiverAddr !== currentTransceiverAddr) {
      try {
        const tx = await transceiverContract.setWormholePeer(
          peer.chainId,
          Buffer.from(desiredTransceiverAddr, "hex")
        );
        log(
          `Registered transceiver peer for chain ${peer.chainId} at ${desiredTransceiverAddr}. Hash: ${tx.hash}`
        );
        await tx.wait();
      } catch (error) {
        log(
          `Error registering transceiver peer for chain ${peer.chainId}: ${error}`
        );
      }
    } else {
      log(
        `Transceiver peer for chain ${peer.chainId} was already registered at ${currentTransceiverAddr}.`
      );
    }

    if (
      (await transceiverContract.isWormholeEvmChain(peer.chainId)) !==
      peer.isWormholeEvmChain
    ) {
      const tx = await transceiverContract.setIsWormholeEvmChain(
        peer.chainId,
        peer.isWormholeEvmChain
      );
      log(
        `Set ${peer.chainId} as wormhole evm chain = ${peer.isWormholeEvmChain}`
      );
      await tx.wait();
    } else {
      log(`Chain ${peer.chainId} is already set as wormhole evm chain.`);
    }

    if (
      (await transceiverContract.isSpecialRelayingEnabled(peer.chainId)) !==
      peer.isSpecialRelayingEnabled
    ) {
      const tx = await transceiverContract.setIsSpecialRelayingEnabled(
        peer.chainId,
        peer.isSpecialRelayingEnabled
      );
      log(
        `Set isSpecialRelayingEnabled for chain ${peer.chainId} to ${peer.isSpecialRelayingEnabled}.`
      );
      await tx.wait();
    } else {
      log(
        `isSpecialRelayingEnabled for chain ${peer.chainId} is already set to ${peer.isSpecialRelayingEnabled}.`
      );
    }

    if (
      (await transceiverContract.isWormholeRelayingEnabled(peer.chainId)) !==
      peer.isWormholeRelayingEnabled
    ) {
      const tx = await transceiverContract.setIsWormholeRelayingEnabled(
        peer.chainId,
        peer.isWormholeRelayingEnabled
      );
      log(
        `Set isWormholeRelayingEnabled for chain ${peer.chainId} to ${peer.isWormholeRelayingEnabled}.`
      );
      await tx.wait();
    } else {
      log(
        `isWormholeRelayingEnabled for chain ${peer.chainId} is already set to ${peer.isWormholeRelayingEnabled}.`
      );
    }
  }

  return { chainId: chain.chainId, peerUpdateTxs };
}

async function getTransceiverContract(chain: ChainInfo) {
  const signer = await getSigner(chain);
  const transceiverAddress = await getContractAddress(
    "NttTransceiverProxies",
    chain.chainId
  );
  return WormholeTransceiver__factory.connect(transceiverAddress, signer);
}

async function getManagerContract(chain: ChainInfo) {
  const signer = await getSigner(chain);
  const managerAddress = await getContractAddress(
    "NttManagerProxies",
    chain.chainId
  );
  return NttManager__factory.connect(managerAddress, signer);
}

async function getNormalizedPeerManagerAddress(
  peer: PeerConfig,
  chain: ChainInfo
) {
  const peerAddress = await getPeerManagerAddress(peer, chain);
  if (!peerAddress) return;
  return tryNativeToHexString(peerAddress, peer.chainId);
}

async function getNormalizedPeerTransceiverAddress(
  peer: PeerConfig,
  chain: ChainInfo
) {
  const peerAddress = await getPeerTransceiverAddress(peer, chain);
  if (!peerAddress) return;
  return tryNativeToHexString(peerAddress, peer.chainId);
}

async function getPeerManagerAddress(peer: PeerConfig, chain: ChainInfo) {
  return (
    peer.managerAddress ??
    (await getContractAddress("NttManagerProxies", peer.chainId))
  );
}

async function getPeerTransceiverAddress(peer: PeerConfig, chain: ChainInfo) {
  return (
    peer.transceiverAddress ??
    (await getContractAddress("NttTransceiverProxies", peer.chainId))
  );
}

run().then(() => console.log("Done!"));

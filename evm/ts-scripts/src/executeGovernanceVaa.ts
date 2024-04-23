import { inspect } from "util";
import { ChainId } from "@certusone/wormhole-sdk";

import {
  loadOperatingChains,
  init,
  ChainInfo,
  getChainConfig,
  getSigner,
  getContractAddress,
} from "./env";
import { Governance__factory } from "../contract-bindings";

const processName = "updatePeerAddresses";

type GovernanceConfig = {
  chainId: ChainId;
  vaa: string;
};

init();
const chains = loadOperatingChains();
async function run() {
  console.log(`Start ${processName}!`);

  const results = await Promise.all(
    chains.map(async (chain) => {
      let result;
      try {
        result = await executeGovernance(chain);
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

    console.log(
      `NttManager set peer txs for chain ${
        result.chainId
      }: \n  ${result.peerUpdateTxs.join("\n  ")}`
    );

    console.log(
      `NttManager set transceiver peer txs for chain ${
        result.chainId
      }: \n  ${result.transceiverUpdateTxs.join("\n  ")}`
    );
  }
}

async function executeGovernance(
  chain: ChainInfo,
) {
  const log = (...args: any[]) => console.log(`[${chain.chainId}]`, ...args);
  const { vaa } = await getChainConfig<GovernanceConfig>("governance-vaas", chain.chainId);
  
  const governanceContract = await getGovernanceContract(chain);

  const vaaHex = Buffer.from(vaa, "base64").toString("hex");
  log("Executing governance with VAA: ", vaaHex);

  const tx = await governanceContract.performGovernance(
    `0x${vaaHex}`,
  );

  log(`Submitted governance transaction: ${tx.hash}`);

  await tx.wait();

  log("success.");
}

run().then(() => console.log("Done!"));

async function getGovernanceContract(chain: ChainInfo) {
  const signer = await getSigner(chain);
  const governanceAddress = await getContractAddress("GeneralPurposeGovernances", chain.chainId);
  return Governance__factory.connect(governanceAddress, signer);
}
import { inspect } from "util";
import { CHAIN_ID_SOLANA, ChainId } from "@certusone/wormhole-sdk";
import {
  WormholeTransceiver__factory,
  NttManager__factory,
  ISpecialRelayer__factory,
  IERC20,
} from "../contract-bindings";
import {
  loadOperatingChains,
  init,
  ChainInfo,
  getSigner,
  getContractAddress,
  loadScriptConfig,
} from "./env";
import { IWormholeRelayer__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts";
import { ERC20__factory } from "../contract-bindings/factories/ERC20Mock.sol";

const processName = "transferTokens";

type Peer = {
  chainId: ChainId;
};

init();
const chains = loadOperatingChains();
async function run() {
  // Warning: we assume that the script configuration file is correctly formed
  console.log(`Start ${processName}!`);
  const peers = (await loadScriptConfig("peers")) as Peer[];

  const results = await Promise.all(
    chains.map(async (chain) => {
      try {
        await trnsferTokens(chain, peers);
      } catch (error) {
        return { chainId: chain.chainId, error };
      }

      return { chainId: chain.chainId };
    })
  );

  for (const result of results) {
    if ("error" in result) {
      console.error(
        `${processName} failed for chain ${result.chainId}: ${inspect(
          result.error
        )}`
      );
      continue;
    }

    console.log(`${processName} succeeded for chain ${result.chainId}`);
  }
}
const zeroAddress32 = "0x" + "00".repeat(32);

async function trnsferTokens(chain: ChainInfo, peers: Peer[]) {
  const log = (...args: any[]) => console.log(`[${chain.chainId}]`, ...args);
  const wormholeRelayerContract = await getWormholeRelayerContract(chain);
  const managerContract = await getManagerContract(chain);
  const specialRelayer = await getSpecializedRelayer(chain);
  const tokenAddress = await managerContract.token();

  const recipientChainId = Number(process.env.TARGET_CHAIN_ID) as ChainId;
  const recipientAddress = process.env.RECIPIENT_ADDRESS as string;

  if (!recipientAddress || !recipientChainId) {
    throw new Error("Invalid recipient address or chain ID");
  }

  log(
    `Quoting delivery price. ${JSON.stringify(
      { tokenAddress, recipientChainId, recipientAddress },
      null,
      2
    )}`
  );

  let deliveryQuote;
  if (recipientChainId === CHAIN_ID_SOLANA) {
    deliveryQuote = await specialRelayer.quoteDeliveryPrice(
      tokenAddress,
      recipientChainId,
      0
    );

    log("specialized relayer quote: ", deliveryQuote.toString());
  } else {
    deliveryQuote = (
      await wormholeRelayerContract[
        "quoteEVMDeliveryPrice(uint16,uint256,uint256)"
      ](recipientChainId, 0, 30_000)
    ).nativePriceQuote;
    log("wormhole relayer quote: ", deliveryQuote.toString());
  }

  const tokenContract = ERC20__factory.connect(tokenAddress, await getSigner(chain));

  const txValue = deliveryQuote.mul(2);
  const approveTx = await (await tokenContract.approve(managerContract.address, txValue));
  const res = await approveTx.wait();

  const transferTx = await managerContract["transfer(uint256,uint16,bytes32,bool,bytes)"](
    "10000000000000",
    recipientChainId,
    recipientAddress,
    false,
    "0x01000100", // one instruction of 1 empty byte
    { value: txValue },
  );

  log("Transfer sent. Receipt:", await transferTx.wait());

  return { chainId: chain.chainId };
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

async function getSpecializedRelayer(chain: ChainInfo) {
  const signer = await getSigner(chain);
  const specializedRelayerAddress = await getContractAddress(
    "SpecializedRelayers",
    chain.chainId
  );
  return ISpecialRelayer__factory.connect(specializedRelayerAddress, signer);
}

async function getWormholeRelayerContract(chain: ChainInfo) {
  const signer = await getSigner(chain);
  const wormholeRelayerAddress = await getContractAddress(
    "WormholeRelayers",
    chain.chainId
  );
  return IWormholeRelayer__factory.connect(wormholeRelayerAddress, signer);
}

run().then(() => console.log("Done!"));

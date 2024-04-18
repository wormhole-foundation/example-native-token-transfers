import {
  Chain,
  ChainAddress,
  ChainContext,
  DEFAULT_TASK_TIMEOUT,
  Network,
  Signer,
  TokenTransfer,
  TransferState,
  TxHash,
  Wormhole,
  api,
  tasks,
} from "@wormhole-foundation/sdk";

import evm from "@wormhole-foundation/sdk/platforms/evm";
import solana from "@wormhole-foundation/sdk/platforms/solana";

// Use .env.example as a template for your .env file and populate it with secrets
// for funded accounts on the relevant chain+network combos to run the example

function getEnv(key: string): string {
  // If we're in the browser, return empty string
  if (typeof process === undefined) return "";

  // Otherwise, return the env var or error
  const val = process.env[key];
  if (!val)
    throw new Error(
      `Missing env var ${key}, did you forget to set valies in '.env'?`
    );

  return val;
}

export interface SignerStuff<N extends Network, C extends Chain> {
  chain: ChainContext<N, C>;
  signer: Signer<N, C>;
  address: ChainAddress<C>;
}

export async function getSigner<N extends Network, C extends Chain>(
  chain: ChainContext<N, C>
): Promise<SignerStuff<N, C>> {
  // Read in from `.env`
  (await import("dotenv")).config();

  let signer: Signer;
  const platform = chain.platform.utils()._platform;
  switch (platform) {
    case "Solana":
      // @ts-ignore
      signer = await solana.getSigner(
        await chain.getRpc(),
        getEnv("OTHER_SOL_PRIVATE_KEY"),
        {
          //debug: true,
          priorityFeePercentile: 0.9,
        }
      );
      break;
    case "Evm":
      // @ts-ignore
      signer = await evm.getSigner(
        await chain.getRpc(),
        getEnv("ETH_PRIVATE_KEY")
      );
      break;
    default:
      throw new Error("Unrecognized platform: " + platform);
  }

  return {
    chain,
    signer: signer as Signer<N, C>,
    address: Wormhole.chainAddress(chain.chain, signer.address()),
  };
}

export async function waitLog<N extends Network = Network>(
  wh: Wormhole<N>,
  xfer: TokenTransfer<N>,
  tag: string = "WaitLog",
  timeout: number = DEFAULT_TASK_TIMEOUT
) {
  const tracker = TokenTransfer.track(
    wh,
    TokenTransfer.getReceipt(xfer),
    timeout
  );
  let receipt;
  for await (receipt of tracker) {
    console.log(
      `${tag}: Current trasfer state: `,
      TransferState[receipt.state]
    );
  }
  return receipt;
}

// Note: This API may change but it is currently the best place to pull
// the relay status from
export async function waitForRelay(
  txid: TxHash
): Promise<api.RelayData | null> {
  const relayerApi = "https://relayer.dev.stable.io";
  const task = () => api.getRelayStatus(relayerApi, txid);
  return tasks.retry<api.RelayData>(
    task,
    5000,
    60 * 1000,
    "Wormhole:GetRelayStatus"
  );
}

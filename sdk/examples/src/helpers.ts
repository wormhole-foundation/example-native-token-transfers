import {
  Chain,
  ChainAddress,
  ChainContext,
  Network,
  Signer,
  Wormhole,
} from "@wormhole-foundation/sdk";

import evm from "@wormhole-foundation/sdk/platforms/evm";
import solana from "@wormhole-foundation/sdk/platforms/solana";

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
      signer = await solana.getSigner(
        await chain.getRpc(),
        getEnv("OTHER_SOL_PRIVATE_KEY"),
        { priorityFeePercentile: 0.9, debug: true }
      );
      break;
    case "Evm":
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

// Use .env.example as a template for your .env file and populate it with secrets
// for funded accounts on the relevant chain+network combos to run the example
function getEnv(key: string): string {
  // If we're in the browser, return empty string
  if (typeof process === undefined) return "";
  // Otherwise, return the env var or error
  const val = process.env[key];
  if (!val)
    throw new Error(
      `Missing env var ${key}, did you forget to set values in '.env'?`
    );

  return val;
}

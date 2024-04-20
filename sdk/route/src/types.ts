import {
  Chain,
  ChainContext,
  Network,
  TokenId,
  VAA,
  Wormhole,
  WormholeMessageId,
  TransferReceipt as _TransferReceipt,
  amount,
  canonicalAddress,
  routes,
} from "@wormhole-foundation/sdk-connect";
import { Ntt } from "@wormhole-foundation/sdk-definitions-ntt";

export namespace NttRoute {
  // Currently only wormhole attestations supported
  export type TransceiverType = "wormhole";

  export type TransceiverConfig = {
    type: TransceiverType;
    address: string;
  };

  export type TokenConfig = {
    chain: Chain;
    token: string;
    manager: string;
    transceiver: TransceiverConfig[];
    quoter?: string;
  };

  export type Config = {
    // Token Name => Config
    tokens: Record<string, TokenConfig[]>;
  };

  /** Options for Per-TransferRequest settings */
  export interface Options {
    automatic: boolean;
    gasDropoff?: string;
  }

  export const ManualOptions: Options = {
    automatic: false,
  };

  export const AutomaticOptions: Options = {
    automatic: true,
    gasDropoff: "0.0",
  };

  export type NormalizedParams = {
    amount: amount.Amount;
    options: Ntt.TransferOptions;
    sourceContracts: Ntt.Contracts;
    destinationContracts: Ntt.Contracts;
  };

  export interface ValidatedParams
    extends routes.ValidatedTransferParams<Options> {
    normalizedParams: NormalizedParams;
  }

  export type AttestationReceipt = {
    id: WormholeMessageId;
    attestation: VAA<"Ntt:WormholeTransfer">;
  };

  export type TransferReceipt<
    SC extends Chain = Chain,
    DC extends Chain = Chain
  > = _TransferReceipt<AttestationReceipt, SC, DC> & {
    params: ValidatedParams;
  };

  export function resolveSupportedNetworks(config: Config): Network[] {
    return ["Mainnet", "Testnet"];
  }

  export function resolveSupportedChains(
    config: Config,
    network: Network
  ): Chain[] {
    const configs = Object.values(config.tokens);
    return configs.flatMap((cfg) => cfg.map((chainCfg) => chainCfg.chain));
  }

  export function resolveSourceTokens(
    config: Config,
    fromChain: ChainContext<Network>
  ): TokenId[] {
    const srcTokens = Object.entries(config.tokens)
      .map(([, configs]) => {
        const tokenConf = configs.find(
          (config) => config.chain === fromChain.chain
        );
        if (!tokenConf) return null;
        return Wormhole.tokenId(fromChain.chain, tokenConf!.token);
      })
      .filter((x) => !!x) as TokenId[];

    // TODO: dedupe?  //return routes.uniqueTokens(srcTokens);
    return srcTokens;
  }

  export function resolveDestinationTokens(
    config: Config,
    sourceToken: TokenId,
    fromChain: ChainContext<Network>,
    toChain: ChainContext<Network>
  ) {
    return Object.entries(config.tokens)
      .map(([, configs]) => {
        const match = configs.find(
          (config) =>
            config.chain === fromChain.chain &&
            config.token.toLowerCase() ===
              canonicalAddress(sourceToken).toLowerCase()
        );
        if (!match) return;

        const remote = configs.find((config) => config.chain === toChain.chain);
        if (!remote) return;

        return Wormhole.tokenId(toChain.chain, remote.token);
      })
      .filter((x) => !!x) as TokenId[];
  }

  export function resolveNttContracts(
    config: Config,
    token: TokenId
  ): Ntt.Contracts {
    const cfg = Object.values(config.tokens);
    const address = canonicalAddress(token);
    for (const tokens of cfg) {
      const found = tokens.find(
        (tc) =>
          tc.token.toLowerCase() === address.toLowerCase() &&
          tc.chain === token.chain
      );
      if (found)
        return {
          token: found.token,
          manager: found.manager,
          transceiver: {
            wormhole: found.transceiver.find((v) => v.type === "wormhole")!
              .address,
          },
          quoter: found.quoter,
        };
    }
    throw new Error("Cannot find Ntt contracts in config for: " + address);
  }
}

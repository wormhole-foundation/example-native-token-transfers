import {
  Chain,
  ChainContext,
  TokenId,
  VAA,
  WormholeMessageId,
  TransferReceipt as _TransferReceipt,
  amount,
  canonicalAddress,
  routes,
  Network,
  Wormhole,
} from "@wormhole-foundation/sdk-connect";
import { Ntt } from "@wormhole-foundation/sdk-definitions-ntt";

export namespace NttRoute {
  // Currently only wormhole attestations supported
  export type TransceiverType = "wormhole";

  export type TokenConfig = {
    chain: Chain;
    token: string;
    manager: string;
    transceiver: [
      {
        type: TransceiverType;
        address: string;
      }
    ];
  };

  export type Config = {
    // Token Name => Config
    tokens: Record<string, TokenConfig[]>;
  };

  /** Options for Per-TransferRequest settings */
  export type Options = {
    /** Whether or not to relay the transfer */
    automatic: boolean;
  };

  export type NormalizedParams = {
    amount: amount.Amount;
    srcNtt: Ntt.Contracts;
    dstNtt: Ntt.Contracts;
  };

  export interface ValidatedParams
    extends routes.ValidatedTransferParams<Options> {
    normalizedParams: NormalizedParams;
  }

  export type AttestationReceipt = {
    id: WormholeMessageId;
    // TODO: any so we dont trip types but attestation type
    // scheme needs thinkin
    attestation: VAA<"Ntt:WormholeTransfer"> | any;
  };

  export type TransferReceipt<
    SC extends Chain = Chain,
    DC extends Chain = Chain
  > = _TransferReceipt<AttestationReceipt, SC, DC>;

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
      if (found) {
        const c: Ntt.Contracts = {
          token: found.token,
          manager: found.manager,
          transceiver: {
            wormhole: found.transceiver.find((v) => v.type === "wormhole")!
              .address,
          },
        };
        return c;
      }
    }
    throw new Error("Cannot find Ntt contracts in config for: " + address);
  }
}

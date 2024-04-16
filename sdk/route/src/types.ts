import {
  Chain,
  TokenId,
  VAA,
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

  export function resolveNttContracts(
    config: Config,
    token: TokenId
  ): Ntt.Contracts {
    const cfg = Object.values(config.tokens);
    const address = canonicalAddress(token);
    for (const tokens of cfg) {
      // TODO: casing of addresses will be an issue,
      // make sure to compare after tolower or smth
      const found = tokens.find(
        (tc) => tc.token === address && tc.chain === token.chain
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

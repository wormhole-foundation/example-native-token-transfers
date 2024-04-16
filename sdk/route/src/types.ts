import {
  Chain,
  WormholeMessageId,
  TransferReceipt as _TransferReceipt,
  amount,
  routes,
} from "@wormhole-foundation/sdk-connect";

export namespace NttRoute {
  // TODO: add more transceiver types here
  export type TransceiverType = "wormhole";

  export type TokenConfig = {
    chain: string;
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
    // map of token name to configs
    tokens: Record<string, TokenConfig[]>;
  };

  export type Options = {
    automatic: boolean;
    // per request options
  };

  export type NormalizedParams = {
    amount: amount.Amount;
  };

  export interface ValidatedParams
    extends routes.ValidatedTransferParams<Options> {
    normalizedParams: NormalizedParams;
  }

  export type AttestationReceipt = {
    id: WormholeMessageId;
    attestation: any;
  };

  export type TransferReceipt<
    SC extends Chain = Chain,
    DC extends Chain = Chain
  > = _TransferReceipt<NttRoute.AttestationReceipt, SC, DC>;
}

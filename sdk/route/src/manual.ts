import type {
  AttestedTransferReceipt,
  Chain,
  ChainContext,
  Network,
  Signer,
  SourceInitiatedTransferReceipt,
  TokenId,
  TransactionId,
  TransferReceipt,
} from "@wormhole-foundation/sdk";
import {
  TransferState,
  Wormhole,
  WormholeMessageId,
  amount,
  canonicalAddress,
  isAttested,
  isSourceFinalized,
  isSourceInitiated,
  routes,
  signSendWait,
} from "@wormhole-foundation/sdk-connect";
import { NttRouteConfig } from "./types.js";
import { Ntt } from "@wormhole-foundation/sdk-definitions-ntt";
import { isQuestionDotToken } from "typescript";
import { isReadable } from "stream";

export namespace NttRoute {
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
}

export type NttAttestationReceipt = {
  id: WormholeMessageId;
  attestation: any;
};

export type NttTransferReceipt<
  SC extends Chain = Chain,
  DC extends Chain = Chain
> = TransferReceipt<NttAttestationReceipt, SC, DC>;

type Op = NttRoute.Options;
type Vp = NttRoute.ValidatedParams;

type Tp = routes.TransferParams<Op>;
type Vr = routes.ValidationResult<Op>;

type QR = routes.QuoteResult<Op, Vp>;
type Q = routes.Quote<Op, Vp>;
type R = NttTransferReceipt;

export class NttRoute<N extends Network>
  extends routes.ManualRoute<N, Op, Vp, R>
  implements routes.StaticRouteMethods<typeof NttRoute>
{
  static config: NttRouteConfig = {
    // enable tokens by adding them to config
    // see the factory below
    tokens: {},
  };

  static meta = {
    name: "ManualNtt",
  };

  static supportedNetworks(): Network[] {
    return ["Mainnet", "Testnet"];
  }
  // get the list of chains this route supports
  static supportedChains(network: Network): Chain[] {
    // TODO
    return ["Solana", "Sepolia"];
  }

  // get the list of source tokens that are possible to send
  static async supportedSourceTokens(
    fromChain: ChainContext<Network>
  ): Promise<TokenId[]> {
    // TODO: dedupe?
    return Object.entries(this.config.tokens)
      .map(([, configs]) => {
        const tokenConf = configs.find((config) => {
          config.chain === fromChain.chain;
        });
        if (!tokenConf) return null;
        return Wormhole.tokenId(fromChain.chain, tokenConf!.token);
      })
      .filter((x) => !!x) as TokenId[];
  }

  // get the list of destination tokens that may be recieved on the destination chain
  static async supportedDestinationTokens<N extends Network>(
    sourceToken: TokenId,
    fromChain: ChainContext<N>,
    toChain: ChainContext<N>
  ): Promise<TokenId[]> {
    // TODO: memoize token address lookup for repeated lookups?
    return Object.entries(this.config.tokens)
      .map(([, configs]) => {
        const match = configs.find((config) => {
          config.chain === fromChain.chain &&
            config.token === canonicalAddress(sourceToken);
        });
        if (!match) return;
        const remote = configs.find((config) => config.chain === toChain.chain);
        if (!remote) return;
        return Wormhole.tokenId(toChain.chain, remote.token);
      })
      .filter((x) => !!x) as TokenId[];
  }

  static isProtocolSupported<N extends Network>(
    chain: ChainContext<N>
  ): boolean {
    return chain.supportsProtocol("Ntt");
  }

  getDefaultOptions(): Op {
    return { automatic: false };
  }

  async validate(params: Tp): Promise<Vr> {
    const amt = amount.parse(params.amount, this.request.source.decimals);

    const validatedParams: Vp = {
      amount: params.amount,
      normalizedParams: { amount: amt },
      options: this.getDefaultOptions(),
    };

    return { valid: true, params: validatedParams };
  }

  async quote(params: Vp): Promise<QR> {
    return {
      success: true,
      params,
      sourceToken: {
        token: this.request.source.id,
        amount: amount.parse(params.amount, this.request.source.decimals),
      },
      destinationToken: {
        token: this.request.destination.id,
        // TODO: wrong probably
        amount: amount.parse(params.amount, this.request.destination.decimals),
      },
    };
  }

  async initiate(signer: Signer, quote: Q): Promise<R> {
    const { params } = quote;
    const { fromChain, from, to } = this.request;
    const sender = Wormhole.parseAddress(signer.chain(), signer.address());
    const ntt = await fromChain.getProtocol("Ntt");
    const initXfer = ntt.transfer(
      sender,
      amount.units(params.normalizedParams.amount),
      to,
      false
    );
    const txids = await signSendWait(fromChain, initXfer, signer);

    return {
      from: from.chain,
      to: to.chain,
      state: TransferState.SourceInitiated,
      originTxs: txids,
    } satisfies SourceInitiatedTransferReceipt;
  }

  async complete(signer: Signer, receipt: R): Promise<TransactionId[]> {
    if (!isAttested(receipt))
      throw new Error(
        "The source must be finalized in order to complete the transfer"
      );

    const { toChain } = this.request;
    const ntt = await toChain.getProtocol("Ntt");
    const sender = Wormhole.parseAddress(signer.chain(), signer.address());
    const completeXfer = ntt.redeem([receipt.attestation], sender);
    return await signSendWait(toChain, completeXfer, signer);
  }

  async finalize(signer: Signer, receipt: R): Promise<TransactionId[]> {
    if (!isRedeemed(receipt))
      throw new Error("The transfer must be redeemed in order to finalize it");

    const completeTransfer = ntt.completeInboundQueuedTransfer(
      fromChain.chain,
      vaa,
      this.request.destination.id.address
    );

    const destinationTxs = await signSendWait(
      toChain,
      completeTransfer,
      signer
    );
    //
  }

  public override async *track(receipt: R, timeout?: number) {
    if (isSourceInitiated(receipt) || isSourceFinalized(receipt)) {
      const { txid } = receipt.originTxs[receipt.originTxs.length - 1]!;
      const vaa = await this.wh.getVaa(txid, "Ntt:WormholeTransfer", timeout);
      if (!vaa) throw new Error("No VAA found for transaction: " + txid);

      const msgId: WormholeMessageId = {
        chain: vaa.emitterChain,
        emitter: vaa.emitterAddress,
        sequence: vaa.sequence,
      };

      yield {
        ...receipt,
        state: TransferState.Attested,
        attestation: { id: msgId, attestation: vaa } as any,
      } satisfies AttestedTransferReceipt<any>;
    }

    const { toChain } = this.request;
    const ntt = (await this.request.toChain.getProtocol("Ntt")) as Ntt<
      N,
      typeof toChain.chain
    >;

    if (isAttested(receipt)) {
      const {
        attestation: { attestation: vaa },
      } = receipt;

      // fist check is redeemed so we can be done
      if (await ntt.getIsRedeemed(vaa)) {
        // TODO: check for destination event transactions?
        yield {
          ...receipt,
          state: TransferState.DestinationFinalized,
          destinationTx: "",
        };
      }
    }

    if (isRedeemed(receipt)) {
      const {
        attestation: { attestation: vaa },
      } = receipt;
      // now check to see if its approved and pending completion
      if (await ntt.getIsApproved(vaa)) {
        yield {
          ...receipt,
          state: TransferState.Attested,
          destinationTx: "",
        };
      }
    }

    // TODO: check for destination transactions

    return receipt;
  }
}

export function nttRoutes<N extends Network>(config: NttRouteConfig) {
  class NttRouteImpl extends NttRoute<N> {
    static override config = config;
  }
  return NttRouteImpl;
}

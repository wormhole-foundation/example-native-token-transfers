import {
  AttestedTransferReceipt,
  Chain,
  ChainContext,
  Network,
  Signer,
  SourceInitiatedTransferReceipt,
  TokenId,
  TransactionId,
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
import "@wormhole-foundation/sdk-definitions-ntt";
import { NttRoute } from "./types.js";

type Op = NttRoute.Options;
type Tp = routes.TransferParams<Op>;
type Vr = routes.ValidationResult<Op>;

type Vp = NttRoute.ValidatedParams;
type QR = routes.QuoteResult<Op, Vp>;
type Q = routes.Quote<Op, Vp>;

type R = NttRoute.TransferReceipt;

export class NttManualRoute<N extends Network>
  extends routes.ManualRoute<N, Op, Vp, R>
  implements routes.StaticRouteMethods<typeof NttManualRoute>
{
  static config: NttRoute.Config = {
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

  // TODO: move more logic from these static methods to
  // the namespace so they can be re-used in the Auto route
  static supportedChains(network: Network): Chain[] {
    const configs = Object.values(this.config.tokens);
    return configs.flatMap((cfg) => cfg.map((chainCfg) => chainCfg.chain));
  }

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
      normalizedParams: {
        amount: amt,
        srcNtt: NttRoute.resolveNttContracts(
          NttManualRoute.config,
          this.request.source.id
        ),
        dstNtt: NttRoute.resolveNttContracts(
          NttManualRoute.config,
          this.request.destination.id
        ),
      },
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
        // TODO: wrong, probably
        amount: amount.parse(params.amount, this.request.destination.decimals),
      },
    };
  }

  async initiate(signer: Signer, quote: Q): Promise<R> {
    const { params } = quote;
    const { fromChain, from, to } = this.request;
    const sender = Wormhole.parseAddress(signer.chain(), signer.address());

    const ntt = await fromChain.getProtocol(
      "Ntt",
      params.normalizedParams.srcNtt
    );
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
    // TODO: get the ntt contracts from..somewhere?
    const ntt = await toChain.getProtocol("Ntt");
    const sender = Wormhole.parseAddress(signer.chain(), signer.address());
    const completeXfer = ntt.redeem([receipt.attestation], sender);
    return await signSendWait(toChain, completeXfer, signer);
  }

  async finalize(signer: Signer, receipt: R): Promise<TransactionId[]> {
    if (!isAttested(receipt))
      throw new Error("The transfer must be attested in order to finalize");

    // TODO:
    //if (!isRedeemed(receipt))
    //  throw new Error("The transfer must be redeemed in order to finalize it");

    const { toChain } = this.request;
    const ntt = await toChain.getProtocol("Ntt");
    const completeTransfer = ntt.completeInboundQueuedTransfer(
      toChain.chain,
      receipt.attestation.attestation.payload.nttManagerPayload,
      this.request.destination.id.address
    );

    return await signSendWait(this.request.toChain, completeTransfer, signer);
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
        attestation: {
          id: msgId,
          attestation: vaa,
        },
      } satisfies AttestedTransferReceipt<NttRoute.AttestationReceipt> as R;
    }

    return receipt as R;
    // const { toChain } = this.request;
    // const ntt = await toChain.getProtocol("Ntt");

    // if (isAttested(receipt)) {
    //   const {
    //     attestation: { attestation: vaa },
    //   } = receipt;

    //   // fist check is redeemed so we can be done
    //   if (await ntt.getIsApproved(vaa)) {
    //     // TODO: check for destination event transactions?
    //     yield {
    //       ...receipt,
    //       state: TransferState.DestinationFinalized,
    //       destinationTx: "",
    //     };
    //   }
    // }

    //if (isRedeemed(receipt)) {
    //  const {
    //    attestation: { attestation: vaa },
    //  } = receipt;
    //  // now check to see if its approved and pending completion
    //  if (await ntt.getIsExecuted(vaa)) {
    //    yield {
    //      ...receipt,
    //      state: TransferState.Attested,
    //    } satisfies NttRoute.TransferReceipt;
    //  }
    //}
    // TODO: check for destination transactions
    //return receipt;
  }
}

export function nttRoutes<N extends Network>(config: NttRoute.Config) {
  class NttRouteImpl extends NttManualRoute<N> {
    static override config = config;
  }
  return NttRouteImpl;
}

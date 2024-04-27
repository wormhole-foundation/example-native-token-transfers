import {
  AttestedTransferReceipt,
  Chain,
  ChainContext,
  CompletedTransferReceipt,
  Network,
  RedeemedTransferReceipt,
  Signer,
  TokenId,
  TransferState,
  Wormhole,
  WormholeMessageId,
  amount,
  isAttested,
  isRedeemed,
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

export function nttManualRoute(config: NttRoute.Config) {
  class NttRouteImpl<N extends Network> extends NttManualRoute<N> {
    static override config = config;
  }
  return NttRouteImpl;
}

export class NttManualRoute<N extends Network>
  extends routes.FinalizableRoute<N, Op, Vp, R>
  implements routes.StaticRouteMethods<typeof NttManualRoute>
{
  override NATIVE_GAS_DROPOFF_SUPPORTED: boolean = false;
  override IS_AUTOMATIC: boolean = false;

  // @ts-ignore
  // Since we set the config on the static class, access it with this param
  // the NttManualRoute.config will always be empty
  readonly staticConfig = this.constructor.config;
  static config: NttRoute.Config = { tokens: {} };

  static meta = { name: "ManualNtt" };

  static supportedNetworks(): Network[] {
    return NttRoute.resolveSupportedNetworks(this.config);
  }

  static supportedChains(network: Network): Chain[] {
    return NttRoute.resolveSupportedChains(this.config, network);
  }

  static async supportedSourceTokens(
    fromChain: ChainContext<Network>
  ): Promise<TokenId[]> {
    return NttRoute.resolveSourceTokens(this.config, fromChain);
  }

  static async supportedDestinationTokens<N extends Network>(
    sourceToken: TokenId,
    fromChain: ChainContext<N>,
    toChain: ChainContext<N>
  ): Promise<TokenId[]> {
    return NttRoute.resolveDestinationTokens(
      this.config,
      sourceToken,
      fromChain,
      toChain
    );
  }

  static isProtocolSupported<N extends Network>(
    chain: ChainContext<N>
  ): boolean {
    return chain.supportsProtocol("Ntt");
  }

  getDefaultOptions(): Op {
    return NttRoute.ManualOptions;
  }

  async validate(params: Tp): Promise<Vr> {
    const options = params.options ?? this.getDefaultOptions();

    const amt = amount.parse(params.amount, this.request.source.decimals);
    const gasDropoff = amount.units(
      amount.parse(
        options.gasDropoff ?? "0.0",
        this.request.toChain.config.nativeTokenDecimals
      )
    );

    const validatedParams: Vp = {
      amount: params.amount,
      normalizedParams: {
        amount: amt,
        sourceContracts: NttRoute.resolveNttContracts(
          this.staticConfig,
          this.request.source.id
        ),
        destinationContracts: NttRoute.resolveNttContracts(
          this.staticConfig,
          this.request.destination.id
        ),
        options: {
          queue: false,
          automatic: false,
          gasDropoff,
        },
      },
      options,
    };
    return { valid: true, params: validatedParams };
  }

  async quote(params: Vp): Promise<QR> {
    return {
      success: true,
      params,
      sourceToken: {
        token: this.request.source.id,
        amount: params.normalizedParams.amount,
      },
      destinationToken: {
        token: this.request.destination.id,
        amount: amount.parse(params.amount, this.request.destination.decimals),
      },
    };
  }

  async initiate(signer: Signer, quote: Q): Promise<R> {
    const { params } = quote;
    const { fromChain, from, to } = this.request;
    const sender = Wormhole.parseAddress(signer.chain(), signer.address());

    const ntt = await fromChain.getProtocol("Ntt", {
      ntt: params.normalizedParams.sourceContracts,
    });
    const initXfer = ntt.transfer(
      sender,
      amount.units(params.normalizedParams.amount),
      to,
      params.normalizedParams.options
    );
    const txids = await signSendWait(fromChain, initXfer, signer);

    return {
      from: from.chain,
      to: to.chain,
      state: TransferState.SourceInitiated,
      originTxs: txids,
      params,
    };
  }

  async complete(signer: Signer, receipt: R): Promise<R> {
    if (!isAttested(receipt)) {
      if (isRedeemed(receipt)) return receipt;
      throw new Error(
        "The source must be finalized in order to complete the transfer"
      );
    }

    const { toChain } = this.request;
    const ntt = await toChain.getProtocol("Ntt", {
      ntt: receipt.params.normalizedParams.destinationContracts,
    });
    const sender = Wormhole.parseAddress(signer.chain(), signer.address());
    const completeXfer = ntt.redeem([receipt.attestation.attestation], sender);

    const txids = await signSendWait(toChain, completeXfer, signer);
    return {
      ...receipt,
      state: TransferState.DestinationInitiated,
      destinationTxs: txids,
    };
  }

  async finalize(signer: Signer, receipt: R): Promise<R> {
    if (!isRedeemed(receipt))
      throw new Error("The transfer must be redeemed in order to finalize");

    const {
      attestation: { attestation: vaa },
    } = receipt;

    const { toChain } = this.request;
    const ntt = await toChain.getProtocol(
      "Ntt",
      receipt.params.normalizedParams.destinationContracts
    );
    const completeTransfer = ntt.completeInboundQueuedTransfer(
      toChain.chain,
      vaa.payload["nttManagerPayload"],
      this.request.destination.id.address
    );
    const finalizeTxids = await signSendWait(toChain, completeTransfer, signer);
    return {
      ...receipt,
      state: TransferState.DestinationFinalized,
      destinationTxs: [...(receipt.destinationTxs ?? []), ...finalizeTxids],
    };
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

      receipt = {
        ...receipt,
        state: TransferState.Attested,
        attestation: {
          id: msgId,
          attestation: vaa,
        },
      } satisfies AttestedTransferReceipt<NttRoute.AttestationReceipt> as R;

      yield receipt;
    }

    const { toChain } = this.request;
    const ntt = await toChain.getProtocol("Ntt", {
      ntt: receipt.params.normalizedParams.destinationContracts,
    });

    if (isAttested(receipt)) {
      const {
        attestation: { attestation: vaa },
      } = receipt;

      if (await ntt.getIsApproved(vaa)) {
        receipt = {
          ...receipt,
          state: TransferState.DestinationInitiated,
          // TODO: check for destination event transactions to get dest Txids
        } satisfies RedeemedTransferReceipt<NttRoute.AttestationReceipt>;
        yield receipt;
      }
    }

    if (isRedeemed(receipt)) {
      const {
        attestation: { attestation: vaa },
      } = receipt;

      if (await ntt.getIsExecuted(vaa)) {
        receipt = {
          ...receipt,
          state: TransferState.DestinationFinalized,
        } satisfies CompletedTransferReceipt<NttRoute.AttestationReceipt>;
        yield receipt;
      }
    }

    yield receipt;
  }
}

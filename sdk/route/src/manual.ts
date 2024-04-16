import {
  AttestedTransferReceipt,
  Chain,
  ChainContext,
  CompletedTransferReceipt,
  Network,
  RedeemedTransferReceipt,
  Signer,
  SourceInitiatedTransferReceipt,
  TokenId,
  TransactionId,
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

export function nttRoutes(config: NttRoute.Config) {
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
    return NttRoute.resolveSourceTokens(this.config, fromChain);
  }

  // get the list of destination tokens that may be recieved on the destination chain
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
    const ntt = await toChain.getProtocol("Ntt", {
      // TODO: get the  destination NTT contracts
    });
    const sender = Wormhole.parseAddress(signer.chain(), signer.address());
    const completeXfer = ntt.redeem([receipt.attestation], sender);
    return await signSendWait(toChain, completeXfer, signer);
  }

  async finalize(signer: Signer, receipt: R): Promise<TransactionId[]> {
    if (!isAttested(receipt))
      throw new Error("The transfer must be attested in order to finalize");

    const {
      attestation: { attestation: vaa },
    } = receipt;

    if (!isRedeemed(receipt))
      throw new Error(
        "The transfer must be redeemed before it can be finalized"
      );

    const { toChain } = this.request;
    const ntt = await toChain.getProtocol("Ntt", {
      //TODO: Get destination chain contracts...
    });
    const completeTransfer = ntt.completeInboundQueuedTransfer(
      toChain.chain,
      vaa.payload.nttManagerPayload,
      this.request.destination.id.address
    );
    return await signSendWait(toChain, completeTransfer, signer);
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

    const { toChain } = this.request;
    const ntt = await toChain.getProtocol("Ntt");

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
      }
    }

    yield receipt;
  }
}

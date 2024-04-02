import {
  Wormhole,
  WormholeMessageId,
  amount,
  canonicalAddress,
  routes,
  signSendWait,
  tokens,
  type AttestedTransferReceipt,
  type Chain,
  type ChainContext,
  type Network,
  type Signer,
  type SourceInitiatedTransferReceipt,
  type TokenId,
  type TransactionId,
  type TransferReceipt,
  TransferState,
  isAttested,
  isSourceFinalized,
  isSourceInitiated,
} from "@wormhole-foundation/sdk-connect";
import { WormholeNttTransceiver } from "@wormhole-foundation/sdk-definitions-ntt";

export namespace NttRoute {
  export type Options = {};

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
  attestation: WormholeNttTransceiver.VAA;
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
type R = TransferReceipt<NttAttestationReceipt>;

export class NttRoute<N extends Network>
  extends routes.ManualRoute<N, Op, Vp, R>
  implements routes.StaticRouteMethods<typeof NttRoute>
{
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
    return Object.values(fromChain.config.tokenMap!)
      .filter((td) => !!td.ntt)
      .map((td) => Wormhole.tokenId(td.chain, td.address));
  }

  // get the list of destination tokens that may be recieved on the destination chain
  static async supportedDestinationTokens<N extends Network>(
    sourceToken: TokenId,
    fromChain: ChainContext<N>,
    toChain: ChainContext<N>
  ): Promise<TokenId[]> {
    const sourceTokenDetails = tokens.filters.byAddress(
      fromChain.config.tokenMap!,
      canonicalAddress(sourceToken)
    );
    if (!sourceTokenDetails || !sourceTokenDetails.ntt) return [];

    const destToken = tokens.filters.bySymbol(
      toChain.config.tokenMap!,
      sourceTokenDetails.symbol
    );
    if (!destToken || destToken.length === 0) return [];
    if (destToken.length > 1)
      throw new Error("Invalid configuration, multiple tokens found");

    const t = destToken[0]!;

    return [Wormhole.tokenId(t.chain, t.address)];
  }

  static isProtocolSupported<N extends Network>(
    chain: ChainContext<N>
  ): boolean {
    return chain.supportsProtocol("Ntt");
  }

  getDefaultOptions(): Op {
    return {};
  }

  async validate(params: Tp): Promise<Vr> {
    const amt = amount.parse(params.amount, this.request.source.decimals);

    const validatedParams: Vp = {
      amount: params.amount,
      normalizedParams: { amount: amt },
      options: {},
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
    const { fromChain, from, to, source } = this.request;
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

    const { toChain, destination } = this.request;
    const ntt = await toChain.getProtocol("Ntt");
    const sender = Wormhole.parseAddress(signer.chain(), signer.address());
    const completeXfer = ntt.redeem([receipt.attestation], sender);
    return await signSendWait(toChain, completeXfer, signer);
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
        attestation: { id: msgId, attestation: vaa },
      } satisfies AttestedTransferReceipt<NttAttestationReceipt>;
    }
    // TODO: check for destination transactions

    return receipt;
  }
}

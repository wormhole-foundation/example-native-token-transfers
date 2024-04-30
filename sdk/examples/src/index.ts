import {
  TransactionId,
  Wormhole,
  signSendWait,
} from "@wormhole-foundation/sdk";
import evm from "@wormhole-foundation/sdk/platforms/evm";
import solana from "@wormhole-foundation/sdk/platforms/solana";

// register protocol implementations
import "@wormhole-foundation/sdk-evm-ntt";
import "@wormhole-foundation/sdk-solana-ntt";

import { TEST_NTT_TOKENS } from "./consts.js";
import { getSigner } from "./helpers.js";

// Recover an in-flight transfer by setting txids here from output of previous run
const recoverTxids: TransactionId[] = [
  // { chain: "Solana", txid: "hZXRs9TEvMWnSAzcgmrEuHsq1C5rbcompy63vkJ2SrXv4a7u6ZBEaJAkBMXKAfScCooDNhN36Jt4PMcDhN8yGjP", },
];

(async function () {
  const wh = new Wormhole("Testnet", [solana.Platform, evm.Platform]);
  const src = wh.getChain("Solana");
  const dst = wh.getChain("ArbitrumSepolia");

  const srcSigner = await getSigner(src);
  const dstSigner = await getSigner(dst);

  const srcNttInit = src.platform.getProtocolInitializer("Ntt");
  const srcNtt = new srcNttInit(
    wh.network,
    src.chain,
    await src.getRpc(),
    {
      ...src.config.contracts,
      ntt: TEST_NTT_TOKENS[src.chain],
    },
    // @ts-ignore
    "1.0.0"
  );

  const dstNttInit = dst.platform.getProtocolInitializer("Ntt");
  const dstNtt = new dstNttInit(wh.network, dst.chain, await dst.getRpc(), {
    ...dst.config.contracts,
    ntt: TEST_NTT_TOKENS[dst.chain],
  });

  console.log("Source signer", srcSigner.address.address);

  const xfer = () =>
    srcNtt.transfer(srcSigner.address.address, 1000n, dstSigner.address, {
      queue: false,
      automatic: false,
      gasDropoff: 0n,
    });

  // Initiate the transfer (or set to recoverTxids to complete transfer)
  const txids: TransactionId[] =
    recoverTxids.length === 0
      ? await signSendWait(src, xfer(), srcSigner.signer)
      : recoverTxids;
  console.log("Source txs", txids);

  const vaa = await wh.getVaa(txids[0]!.txid, "Ntt:WormholeTransfer");
  console.log(vaa);

  const dstTxids = await signSendWait(
    dst,
    dstNtt.redeem([vaa!]),
    dstSigner.signer
  );
  console.log("dstTxids", dstTxids);
})();

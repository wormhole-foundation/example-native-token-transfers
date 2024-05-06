import {
  TransactionId,
  Wormhole,
  amount,
  signSendWait,
} from "@wormhole-foundation/sdk";
import evm from "@wormhole-foundation/sdk/platforms/evm";
import solana from "@wormhole-foundation/sdk/platforms/solana";

// register protocol implementations
import "@wormhole-foundation/sdk-evm-ntt";
import "@wormhole-foundation/sdk-solana-ntt";

import { TEST_NTT_SPL22_TOKENS, TEST_NTT_TOKENS } from "./consts.js";
import { getSigner } from "./helpers.js";

const TOKEN_CONTRACTS = TEST_NTT_TOKENS;
//const TOKEN_CONTRACTS = TEST_NTT_SPL22_TOKENS;

// Recover an in-flight transfer by setting txids here from output of previous run
const recoverTxids: TransactionId[] = [
  //{ chain: "Solana", txid: "hZXRs9TEvMWnSAzcgmrEuHsq1C5rbcompy63vkJ2SrXv4a7u6ZBEaJAkBMXKAfScCooDNhN36Jt4PMcDhN8yGjP", },
  // Unused adn staged
  // {chain "Sepolia", txid: "0x9f2b1a8124f8377d77deb5c85f165c290669587b494c598beacea60a4d9a00fd"}
  // {chain "Sepolia", txid: "0x1aff02ed4bf9d51a424626187e3e331304229fc0d422b7abfe8025452b166180"}
];

(async function () {
  const wh = new Wormhole("Testnet", [solana.Platform, evm.Platform]);
  const src = wh.getChain("Solana");
  const dst = wh.getChain("Sepolia");

  const srcSigner = await getSigner(src);
  const dstSigner = await getSigner(dst);

  const srcNtt = await src.getProtocol("Ntt", {
    ntt: TOKEN_CONTRACTS[src.chain],
  });
  const dstNtt = await dst.getProtocol("Ntt", {
    ntt: TOKEN_CONTRACTS[dst.chain],
  });

  const amt = amount.units(
    amount.parse("0.01", await srcNtt.getTokenDecimals())
  );

  const xfer = () =>
    srcNtt.transfer(srcSigner.address.address, amt, dstSigner.address, {
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

  const vaa = await wh.getVaa(
    txids[0]!.txid,
    "Ntt:WormholeTransfer",
    25 * 60 * 1000
  );
  console.log(vaa);

  const dstTxids = await signSendWait(
    dst,
    dstNtt.redeem([vaa!], dstSigner.address.address),
    dstSigner.signer
  );
  console.log("dstTxids", dstTxids);
})();

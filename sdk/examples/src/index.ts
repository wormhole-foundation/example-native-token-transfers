import {
  TransactionId,
  signSendWait,
  wormhole,
} from "@wormhole-foundation/sdk";
import evm from "@wormhole-foundation/sdk/evm";
import solana from "@wormhole-foundation/sdk/solana";

// register protocol implementations
import "@wormhole-foundation/sdk-evm-ntt";
import "@wormhole-foundation/sdk-solana-ntt";

import { YUKA_NTT_CONTRACTS } from "./consts.js";
import { getSigner } from "./helpers.js";

// Recover an in-flight transfer by setting txids here from output of previous run
const recoverTxids: TransactionId[] = [
  //{
  //  chain: "Sepolia",
  //  txid: "0x6312a3b1c40792afc3f2e145f343e16ca643808ea6bd4aa641393c5091474413",
  //},
];

(async function () {
  const wh = await wormhole("Testnet", [solana, evm]);
  const src = wh.getChain("Sepolia");
  const dst = wh.getChain("Solana");

  const srcSigner = await getSigner(src);
  const dstSigner = await getSigner(dst);

  const srcNtt = await src.getProtocol("Ntt", {
    ntt: YUKA_NTT_CONTRACTS[src.chain],
  });
  const dstNtt = await dst.getProtocol("Ntt", {
    ntt: YUKA_NTT_CONTRACTS[dst.chain],
  });

  // Initiate the transfer (or set to recoverTxids to complete transfer)
  const txids: TransactionId[] =
    recoverTxids.length === 0
      ? await signSendWait(
          src,
          srcNtt.transfer(srcSigner.address.address, 1000n, dstSigner.address, {
            queue: false,
            automatic: false,
            gasDropoff: 0n,
          }),
          srcSigner.signer
        )
      : recoverTxids;
  console.log("Source txs", txids);

  const vaa = await wh.getVaa(
    txids[txids.length - 1]!.txid,
    "Ntt:WormholeTransfer"
  );
  console.log(vaa);

  const dstTxids = await signSendWait(
    dst,
    dstNtt.redeem([vaa!], dstSigner.address.address),
    dstSigner.signer
  );
  console.log("dstTxids", dstTxids);
})();

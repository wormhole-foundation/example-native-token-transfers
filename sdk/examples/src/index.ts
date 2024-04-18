import {
  TransactionId,
  signSendWait,
  wormhole,
} from "@wormhole-foundation/sdk";
import evm from "@wormhole-foundation/sdk/evm";
import solana from "@wormhole-foundation/sdk/solana";

// register protocol implementations
import { Ntt } from "@wormhole-foundation/sdk-definitions-ntt";
import "@wormhole-foundation/sdk-evm-ntt";
import "@wormhole-foundation/sdk-solana-ntt";

import { getSigner } from "./helpers.js";

const NTT_CONTRACTS: Record<string, Ntt.Contracts> = {
  Solana: {
    token: "E3W7KwMH8ptaitYyWtxmfBUpqcuf2XieaFtQSn1LVXsA",
    manager: "WZLm4bJU4BNVmzWEwEzGVMQ5XFUc4iBmMSLutFbr41f",
    transceiver: {
      wormhole: "WZLm4bJU4BNVmzWEwEzGVMQ5XFUc4iBmMSLutFbr41f",
    },
  },
  ArbitrumSepolia: {
    token: "0x87579Dc40781e99b870DDce46e93bd58A0e58Ae5",
    manager: "0xdA5a8e05e276AAaF4d79AB5b937a002E5221a4D8",
    transceiver: {
      wormhole: "0xd2940c256a3D887833D449eF357b6D639Cb98e12",
    },
  },
};

(async function () {
  const wh = await wormhole("Testnet", [solana, evm]);
  const src = wh.getChain("Solana");
  const dst = wh.getChain("ArbitrumSepolia");

  const srcSigner = await getSigner(src);
  const dstSigner = await getSigner(dst);

  const srcNtt = await src.getProtocol("Ntt", {
    ...src.config.contracts,
    ntt: NTT_CONTRACTS[src.chain],
  });
  const dstNtt = await dst.getProtocol("Ntt", {
    ...dst.config.contracts,
    ntt: NTT_CONTRACTS[dst.chain],
  });

  // Recover an in-flight transfer by setting txids here from output of previous run
  let txids: TransactionId[] = [
    {
      chain: "Solana",
      txid: "hZXRs9TEvMWnSAzcgmrEuHsq1C5rbcompy63vkJ2SrXv4a7u6ZBEaJAkBMXKAfScCooDNhN36Jt4PMcDhN8yGjP",
    },
  ];

  if (txids.length === 0) {
    const xfer = srcNtt.transfer(
      srcSigner.address.address,
      1000n,
      dstSigner.address,
      false
    );
    txids = await signSendWait(src, xfer, srcSigner.signer);
    console.log("Source txs", txids);
  }

  const vaa = await wh.getVaa(txids[0]!.txid, "Ntt:WormholeTransfer");
  console.log(vaa);

  const dstRedeem = dstNtt.redeem([vaa!]);
  const dstTxids = await signSendWait(dst, dstRedeem, dstSigner.signer);
  console.log("dstTxids", dstTxids);
})();

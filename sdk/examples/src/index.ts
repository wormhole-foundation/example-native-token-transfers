import { signSendWait, wormhole } from "@wormhole-foundation/sdk";
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
    manager: "FKtzKFdyaKgzHy7h7RQb4LdkVPRTGi35w6qeim4z5JbG",
    transceiver: {
      wormhole: "FKtzKFdyaKgzHy7h7RQb4LdkVPRTGi35w6qeim4z5JbG",
    },
  },
  ArbitrumSepolia: {
    token: "0x87579Dc40781e99b870DDce46e93bd58A0e58Ae5",
    manager: "0xed9a1ff0abb04b80de902eafbdfb102dc03d5a01",
    transceiver: {
      wormhole: "0xAdD02F468f954d90340C831e839Cf71B09cCb178",
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
  let txids = [
    {
      chain: "Solana",
      txid: "3pRvFCfw3QBQqkjGYFfSDLy4E58YPtGueepJvwEntkEoWJZmKwXjHJ32YEf1WYzTX1ozBnZGrvC1ReyS18boLmqf",
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

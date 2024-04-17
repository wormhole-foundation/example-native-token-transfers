import { signSendWait, wormhole } from "@wormhole-foundation/sdk";
import evm from "@wormhole-foundation/sdk/evm";
import solana from "@wormhole-foundation/sdk/solana";

import "@wormhole-foundation/sdk-definitions-ntt";
import "@wormhole-foundation/sdk-evm-ntt";
import "@wormhole-foundation/sdk-solana-ntt";
import { getSigner } from "./helpers.js";

(async function () {
  const wh = await wormhole("Testnet", [solana, evm]);
  const sol = wh.getChain("Solana");
  const arb = wh.getChain("ArbitrumSepolia");

  //const sendSigner = await getSigner(sol);
  const rcvSigner = await getSigner(arb);

  const originNtt = await sol.getProtocol("Ntt", {
    ...sol.config.contracts,
    ntt: {
      token: "E3W7KwMH8ptaitYyWtxmfBUpqcuf2XieaFtQSn1LVXsA",
      manager: "FKtzKFdyaKgzHy7h7RQb4LdkVPRTGi35w6qeim4z5JbG",
      transceiver: {
        wormhole: "FKtzKFdyaKgzHy7h7RQb4LdkVPRTGi35w6qeim4z5JbG",
      },
    },
  });

  console.log(await originNtt.getCurrentOutboundCapacity());
  console.log(await originNtt.getCurrentInboundCapacity("ArbitrumSepolia"));

  //const xfer = originNtt.transfer(
  //  sendSigner.address.address,
  //  1000n,
  //  rcvSigner.address,
  //  false
  //);

  const txids = [
    {
      chain: "Solana",
      txid: "3pRvFCfw3QBQqkjGYFfSDLy4E58YPtGueepJvwEntkEoWJZmKwXjHJ32YEf1WYzTX1ozBnZGrvC1ReyS18boLmqf",
    },
  ];

  //const txids = await signSendWait(sol, xfer, sendSigner.signer);
  //console.log("Source txs", txids);

  const vaa = await wh.getVaa(txids[0]!.txid, "Ntt:WormholeTransfer");

  console.log(vaa);

  const dstNtt = await arb.getProtocol("Ntt", {
    ...arb.config.contracts,
    ntt: {
      token: "0x87579Dc40781e99b870DDce46e93bd58A0e58Ae5",
      manager: "0xed9a1ff0abb04b80de902eafbdfb102dc03d5a01",
      transceiver: {
        wormhole: "0xAdD02F468f954d90340C831e839Cf71B09cCb178",
      },
    },
  });

  const dstRedeem = dstNtt.redeem([vaa!]);
  const dstTxids = await signSendWait(arb, dstRedeem, rcvSigner.signer);
  console.log("dstTxids", dstTxids);
})();

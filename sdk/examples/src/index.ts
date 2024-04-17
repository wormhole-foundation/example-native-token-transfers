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

  const sendSigner = await getSigner(sol);
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

  const xfer = originNtt.transfer(
    sendSigner.address.address,
    1000n,
    rcvSigner.address,
    false
  );

  console.log(await signSendWait(sol, xfer, sendSigner.signer));
})();

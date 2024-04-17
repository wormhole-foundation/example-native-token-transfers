import { wormhole } from "@wormhole-foundation/sdk";
import solana from "@wormhole-foundation/sdk/solana";
import evm from "@wormhole-foundation/sdk/evm";

import "@wormhole-foundation/sdk-definitions-ntt";
import "@wormhole-foundation/sdk-evm-ntt";
import "@wormhole-foundation/sdk-solana-ntt";

(async function () {
  const wh = await wormhole("Testnet", [solana, evm]);
  const sol = wh.getChain("Solana");
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
})();

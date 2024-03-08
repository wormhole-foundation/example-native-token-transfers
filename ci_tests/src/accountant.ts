import {
  getWallet,
  getWormchainSigningClient,
} from "@wormhole-foundation/wormchain-sdk";
import { ZERO_FEE } from "@wormhole-foundation/wormchain-sdk/lib/core/consts";
import { toUtf8 } from "cosmwasm";

// cache the client and signer
let client: Awaited<ReturnType<typeof getWormchainSigningClient>>;
let signer: string;

export async function submitAccountantVAA(vaa: Uint8Array) {
  if (!signer) {
    // NttAccountantTest = wormhole18s5lynnmx37hq4wlrw9gdn68sg2uxp5rwf5k3u
    const wallet = await getWallet(
      "quality vacuum heart guard buzz spike sight swarm shove special gym robust assume sudden deposit grid alcohol choice devote leader tilt noodle tide penalty"
    );
    client = await getWormchainSigningClient("http://wormchain:26657", wallet);
    const signers = await wallet.getAccounts();
    signer = signers[0].address;
  }
  const msg = client.wasm.msgExecuteContract({
    sender: signer,
    contract:
      "wormhole17p9rzwnnfxcjp32un9ug7yhhzgtkhvl9jfksztgw5uh69wac2pgshdnj3k",
    msg: toUtf8(
      JSON.stringify({
        submit_vaas: {
          vaas: [Buffer.from(vaa).toString("base64")],
        },
      })
    ),
    funds: [],
  });
  const result = await client.signAndBroadcast(signer, [msg], {
    ...ZERO_FEE,
    gas: "10000000",
  });
  if (result.code !== 0) {
    throw new Error(`Bad result: ${result.rawLog}`);
  }
  console.log(`Accountant tx submitted: ${result.transactionHash}`);
}

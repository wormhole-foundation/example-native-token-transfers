import { encoding } from "@wormhole-foundation/sdk-base";
import {
  getWallet,
  getWormchainSigningClient,
} from "@wormhole-foundation/wormchain-sdk";

export const ZERO_FEE = {
  amount: [{ amount: "0", denom: "uworm" }],
  gas: "200000",
};

// cache the client and signer
let client: Awaited<ReturnType<typeof getWormchainSigningClient>>;
let signer: string;

const privateKey =
  "quality vacuum heart guard buzz spike sight swarm shove special gym robust assume sudden deposit grid alcohol choice devote leader tilt noodle tide penalty";
const url = process.env["CI"]
  ? "http://wormchain:26657"
  : "http://localhost:26659";

export async function submitAccountantVAA(vaa: Uint8Array) {
  if (!signer) {
    // NttAccountantTest = wormhole18s5lynnmx37hq4wlrw9gdn68sg2uxp5rwf5k3u
    const wallet = await getWallet(privateKey);
    client = await getWormchainSigningClient(url, wallet);
    const signers = await wallet.getAccounts();
    signer = signers[0]!.address;
  }
  const msg = client.wasm.msgExecuteContract({
    sender: signer,
    contract:
      "wormhole17p9rzwnnfxcjp32un9ug7yhhzgtkhvl9jfksztgw5uh69wac2pgshdnj3k",
    msg: encoding.bytes.encode(
      JSON.stringify({
        submit_vaas: {
          vaas: [encoding.b64.encode(vaa)],
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

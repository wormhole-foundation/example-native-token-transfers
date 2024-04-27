import { Chain } from "@wormhole-foundation/sdk";
import { deploy, link, transferWithChecks, wh } from "./utils.js";
import { submitAccountantVAA } from "./accountant.js";

// Note: Currently, in order for this to run, the evm bindings with extra contracts must be build
// To do that, at the root, run `npm run generate:test`

const cases = [
  ["Solana", ["Ethereum", "Bsc"]],
  ["Ethereum", ["Bsc", "Solana"]],
  // ["Bsc", ["Ethereum", "Solana"]],
];

async function registerRelayers() {
  try {
    await submitAccountantVAA(
      Buffer.from(
        "010000000001006c9967aee739944b30ffcc01653f2030ea02c038adda26a8f5a790f191134dff1e1e48368af121a34806806140d4f56ec09e25067006e69c95b0c4c08b8897990000000000000000000001000000000000000000000000000000000000000000000000000000000000000400000000001ce9cf010000000000000000000000000000000000576f726d686f6c6552656c61796572010000000200000000000000000000000053855d4b64e9a3cf59a84bc768ada716b5536bc5",
        "hex"
      )
    );
  } catch (e) {
    console.log(e);
  }

  try {
    await submitAccountantVAA(
      Buffer.from(
        "01000000000100894be2c33626547e665cee73684854fbd8fc2eb79ec9ad724b1fb10d6cd24aaa590393870e6655697cd69d5553881ac8519e1282e7d3ae5fc26d7452d097651c00000000000000000000010000000000000000000000000000000000000000000000000000000000000004000000000445fb0b010000000000000000000000000000000000576f726d686f6c6552656c61796572010000000400000000000000000000000053855d4b64e9a3cf59a84bc768ada716b5536bc5",
        "hex"
      )
    );
  } catch (e) {
    console.log(e);
  }
}

describe("Hub and Spoke Tests", function () {
  beforeAll(async () => {
    await registerRelayers();
  });

  test.each(cases)("Test %s Hub", async (source, destinations) => {
    // Get chain context objects
    const hubChain = wh.getChain(source as Chain);

    const [a, b] = destinations;
    const spokeChainA = wh.getChain(a as Chain);
    const spokeChainB = wh.getChain(b as Chain);

    // Deploy contracts for hub chain
    console.log("Deploying contracts");
    const [hub, spokeA, spokeB] = await Promise.all([
      deploy({ context: hubChain, mode: "locking" }),
      deploy({ context: spokeChainA, mode: "burning" }),
      deploy({ context: spokeChainB, mode: "burning" }),
    ]);

    console.log("Deployed: ", {
      [hub.context.chain]: hub.contracts,
      [spokeA.context.chain]: spokeA.contracts,
      [spokeB.context.chain]: spokeB.contracts,
    });

    // Link contracts
    console.log("Linking Peers");
    await link([hub, spokeA, spokeB]);

    // Transfer tokens from hub to spoke and check balances
    console.log("Transfer hub to spoke A");
    await transferWithChecks(hub, spokeA);

    // Transfer between spokes and check balances
    console.log("Transfer spoke A to spoke B");
    await transferWithChecks(spokeA, spokeB);

    // Transfer back to hub and check balances
    console.log("Transfer spoke B to hub");
    await transferWithChecks(spokeB, hub);
  });
});

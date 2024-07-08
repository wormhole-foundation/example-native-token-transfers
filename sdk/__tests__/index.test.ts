import { Chain } from "@wormhole-foundation/sdk-base";
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
        "01000000000100a4f34c530ff196c060ff349f2bf7bcb16865771a7165ca84fb5e263f148a01b03592b9af46a410a3760f39097d7380e4e72b6e1da4fa25c2d7b2d00f102d0cae0100000000000000000001000000000000000000000000000000000000000000000000000000000000000400000000001ce9cf010000000000000000000000000000000000576f726d686f6c6552656c617965720100000002000000000000000000000000cc680d088586c09c3e0e099a676fa4b6e42467b4",
        "hex"
      )
    );
  } catch (e) {
    console.log(e);
  }

  try {
    await submitAccountantVAA(
      Buffer.from(
        "010000000001000fd839cfdbea0f43a35dbb8cc0219b55cd5ec9f59b7e4a7183dbeebd522f7c673c866a218bfa108d8c7606acb5fc6b94a7a4c3be06f10836c242afecdb80da6e00000000000000000000010000000000000000000000000000000000000000000000000000000000000004000000000445fb0b010000000000000000000000000000000000576f726d686f6c6552656c617965720100000004000000000000000000000000cc680d088586c09c3e0e099a676fa4b6e42467b4",
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

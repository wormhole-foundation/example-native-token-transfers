import { Chain } from "@wormhole-foundation/sdk";
import { deploy, link, transferWithChecks, wh } from "./utils.js";

// Note: Currently, in order for this to run, the evm bindings with extra contracts must be build
// To do that, at the root, run `npm run generate:test`

const cases = [
  ["Solana", ["Ethereum", "Bsc"]],
  ["Ethereum", ["Bsc", "Solana"]],
  // ["Bsc", ["Ethereum", "Solana"]],
];

describe("Hub and Spoke Tests", function () {
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

    console.log(
      "Deployed: ",
      { chain: hub.context.chain, ...hub.contracts },
      { chain: spokeA.context.chain, ...spokeA.contracts },
      { chain: spokeB.context.chain, ...spokeB.contracts }
    );

    // Link contracts
    console.log("Linking Peers");
    await link([hub, spokeA, spokeB]);

    // Transfer tokens from hub to spoke and check balances
    console.log("Transfer hub to spoke A");
    await transferWithChecks(hub, spokeA);

    // tmp
    await transferWithChecks(spokeA, hub);

    // // Transfer between spokes and check balances
    // console.log("Transfer spoke A to spoke B");
    // await transferWithChecks(spokeA, spokeB);

    // // Transfer back to hub and check balances
    // console.log("Transfer spoke B to hub");
    // await transferWithChecks(spokeB, hub);
  });
});

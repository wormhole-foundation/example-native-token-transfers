import { Wormhole } from "@wormhole-foundation/sdk-connect";
import { EvmPlatform } from "@wormhole-foundation/sdk-evm";
import { EvmNtt } from "../src/index.js";

const wh = new Wormhole("Testnet", [EvmPlatform]);

const overrides = {
  Sepolia: {
    token: "0x738141EFf659625F2eAD4feECDfCD94155C67f18",
    manager: "0x06413c42e913327Bc9a08B7C1E362BAE7C0b9598",
    transceiver: {
      wormhole: "0x649fF7B32C2DE771043ea105c4aAb2D724497238",
    },
  },
};

describe("ABI Versions Test", function () {
  const ctx = wh.getChain("Sepolia");
  test("It initializes from Rpc", async function () {
    const ntt = await EvmNtt.fromRpc(await ctx.getRpc(), {
      Sepolia: {
        ...ctx.config,
        contracts: { ...{ ntt: overrides["Sepolia"] } },
      },
    });
    expect(ntt).toBeTruthy();
  });

  test("It initializes from constructor", async function () {
    const ntt = new EvmNtt("Testnet", "Sepolia", await ctx.getRpc(), {
      ...ctx.config.contracts,
      ...{ ntt: overrides["Sepolia"] },
    });
    expect(ntt).toBeTruthy();
  });

  test("It gets the correct version", async function () {
    const { manager } = overrides["Sepolia"];
    const version = await EvmNtt._getVersion(manager, await ctx.getRpc());
    expect(version).toBe("1.0.0");
  });
});

import { Wormhole } from "@wormhole-foundation/sdk-connect";
import { EvmPlatform } from "@wormhole-foundation/sdk-evm";
import { EvmNtt } from "../src/index.js";

const wh = new Wormhole("Testnet", [EvmPlatform]);

const overrides = {
  Avalanche: {
    token: "0x72CAaa7e9889E0a63e016748179b43911A3ec9e5",
    manager: "0x22D00F8aCcC2da440c937104BA49AfD8261a660F",
    transceiver: {
      wormhole: "0xeA8D34fa9147863e486d2d07AB92b8218CF58C0E",
    },
  },
};

describe("ABI Versions Test", function () {
  const ctx = wh.getChain("Avalanche");
  test("It initializes from Rpc", async function () {
    const ntt = await EvmNtt.fromRpc(await ctx.getRpc(), {
      Avalanche: {
        ...ctx.config,
        //@ts-ignore
        contracts: { ...{ ntt: overrides["Avalanche"] } },
      },
    });
    expect(ntt).toBeTruthy();
  });

  test("It initializes from constructor", async function () {
    const ntt = new EvmNtt("Testnet", "Avalanche", await ctx.getRpc(), {
      ...ctx.config.contracts,
      //@ts-ignore
      ...{ ntt: overrides["Avalanche"] },
    });
    expect(ntt).toBeTruthy();
  });

  test("It gets the correct version", async function () {
    const { manager } = overrides["Avalanche"];
    const version = await EvmNtt.getVersion(manager, await ctx.getRpc());
    expect(version).toBe("0.1.0");
  });
});

import {
  Network,
  Wormhole,
  canonicalAddress,
  routes,
  testing,
} from "@wormhole-foundation/sdk-connect";

import "@wormhole-foundation/sdk-definitions-ntt";
import "@wormhole-foundation/sdk-evm-ntt";
import "@wormhole-foundation/sdk-solana-ntt";

import { EvmPlatform } from "@wormhole-foundation/sdk-evm";
import { SolanaPlatform } from "@wormhole-foundation/sdk-solana";
import { nttRoutes } from "../src/manual.js";
import { NttRoute } from "../src/types.js";

const SOL_TOKEN = "EetppHswYvV1jjRWoQKC1hejdeBDHR9NNzNtCyRQfrrQ";
const SEPOLIA_TOKEN = "0x738141EFf659625F2eAD4feECDfCD94155C67f18";

const conf: NttRoute.Config = {
  tokens: {
    TestToken: [
      {
        chain: "Solana",
        token: SOL_TOKEN,
        manager: "NTtAaoDJhkeHeaVUHnyhwbPNAN6WgBpHkHBTc6d7vLK",
        transceiver: [
          {
            type: "wormhole",
            address: "ExVbjD8inGXkt7Cx8jVr4GF175sQy1MeqgfaY53Ah8as",
          },
        ],
      },
      {
        chain: "Sepolia",
        token: SEPOLIA_TOKEN,
        manager: "0x649fF7B32C2DE771043ea105c4aAb2D724497238",
        transceiver: [
          {
            type: "wormhole",
            address: "0x06413c42e913327Bc9a08B7C1E362BAE7C0b9598",
          },
        ],
      },
    ],
  },
};
const network: Network = "Testnet";

describe("Manual Route Tests", function () {
  const wh = new Wormhole("Testnet", [SolanaPlatform, EvmPlatform]);
  const fromChain = wh.getChain("Solana");
  const toChain = wh.getChain("Sepolia");

  let rt: routes.RouteConstructor;
  it("Should create a Route Constructor given ntt config", function () {
    rt = nttRoutes(conf);
    expect(rt).toBeTruthy();
  });

  it("Should return supported chains", function () {
    const supportedChains = rt.supportedChains(network);
    expect(supportedChains).toEqual(["Solana", "Sepolia"]);
  });

  it("Should return supported tokens", async function () {
    const tokens = await rt.supportedSourceTokens(fromChain);
    expect(tokens).toHaveLength(1);
    expect(canonicalAddress(tokens[0]!)).toEqual(SOL_TOKEN);
  });

  it("Should correctly return corresponding destination token", async function () {
    const token = Wormhole.tokenId("Solana", SOL_TOKEN);
    const tokens = await rt.supportedDestinationTokens(
      token,
      fromChain,
      toChain
    );
    expect(tokens).toHaveLength(1);
    expect(canonicalAddress(tokens[0]!)).toEqual(SEPOLIA_TOKEN);
  });

  let resolver: routes.RouteResolver<Network>;
  it("Should satisfy resolver", async function () {
    resolver = new routes.RouteResolver(wh, [rt]);
  });

  it("Should resolve a given route request", async function () {
    const request = await routes.RouteTransferRequest.create(wh, {
      from: testing.utils.makeChainAddress("Solana"),
      to: testing.utils.makeChainAddress("Sepolia"),
      source: Wormhole.tokenId("Solana", SOL_TOKEN),
      destination: Wormhole.tokenId("Sepolia", SEPOLIA_TOKEN),
    });
    const found = await resolver.findRoutes(request);
    console.log(found);
    expect(found).toHaveLength(1);
    expect(found[0]!.request.from.chain).toEqual("Solana");
  });
});

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
import { nttManualRoute } from "../src/manual.js";
import { NttRoute } from "../src/types.js";
import { nttAutomaticRoute } from "../src/automatic.js";

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
        quoter: "Nqd6XqA8LbsCuG8MLWWuP865NV6jR1MbXeKxD4HLKDJ",
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
    rt = nttManualRoute(conf);
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

  let found: routes.ManualRoute<Network>;
  it("Should resolve a given route request", async function () {
    const request = await routes.RouteTransferRequest.create(wh, {
      from: testing.utils.makeChainAddress("Solana"),
      to: testing.utils.makeChainAddress("Sepolia"),
      source: Wormhole.tokenId("Solana", SOL_TOKEN),
      destination: Wormhole.tokenId("Sepolia", SEPOLIA_TOKEN),
    });
    const foundRoutes = await resolver.findRoutes(request);
    expect(foundRoutes).toHaveLength(1);
    expect(foundRoutes[0]!.request.from.chain).toEqual("Solana");

    const rt = foundRoutes[0]!;
    if (!routes.isManual(rt)) throw new Error("Expected manual route");

    found = rt;
  });

  let op: ReturnType<typeof found.getDefaultOptions>;
  it("Should provide default options", async function () {
    op = found.getDefaultOptions();
    expect(op).toBeTruthy();
  });

  let vp: routes.ValidationResult<typeof op>;
  it("Should validate a transfer request", async function () {
    vp = await found.validate({ amount: "1.0", options: op });
    expect(vp.valid).toBeTruthy();
    expect(vp.params.amount).toEqual("1.0");
  });

  let qr: Awaited<ReturnType<typeof found.quote>>;
  it("Should fetch a quote given the validated parameters", async function () {
    if (!vp.valid) throw new Error("Invalid transfer params used");
    qr = await found.quote(vp.params);
    if (!qr.success) throw new Error("Failed to fetch quote");

    expect(qr.params.amount).toEqual("1.0");

    const srcAddy = canonicalAddress(qr.sourceToken.token);
    expect(srcAddy).toEqual(SOL_TOKEN);

    const dstAddy = canonicalAddress(qr.destinationToken.token);
    expect(dstAddy).toEqual(SEPOLIA_TOKEN);

    // No fees or other fields
    expect(Object.keys(qr)).toEqual([
      "success",
      "params",
      "sourceToken",
      "destinationToken",
    ]);
  });
});

describe("Automatic Route Tests", function () {
  const wh = new Wormhole("Testnet", [SolanaPlatform, EvmPlatform]);
  const fromChain = wh.getChain("Solana");
  const toChain = wh.getChain("Sepolia");

  let rt: routes.RouteConstructor;
  it("Should create a Route Constructor given ntt config", function () {
    rt = nttAutomaticRoute(conf);
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

  let found: routes.AutomaticRoute<Network>;
  it("Should resolve a given route request", async function () {
    const request = await routes.RouteTransferRequest.create(wh, {
      from: testing.utils.makeChainAddress("Solana"),
      to: testing.utils.makeChainAddress("Sepolia"),
      source: Wormhole.tokenId("Solana", SOL_TOKEN),
      destination: Wormhole.tokenId("Sepolia", SEPOLIA_TOKEN),
    });
    const foundRoutes = await resolver.findRoutes(request);
    expect(foundRoutes).toHaveLength(1);
    expect(foundRoutes[0]!.request.from.chain).toEqual("Solana");

    const rt = foundRoutes[0]!;
    if (!routes.isAutomatic(rt)) throw new Error("Expected automatic route");

    found = rt;
  });

  let op: ReturnType<typeof found.getDefaultOptions>;
  it("Should provide default options", async function () {
    op = found.getDefaultOptions();
    expect(op).toBeTruthy();
  });

  let vp: routes.ValidationResult<typeof op>;
  it("Should validate a transfer request", async function () {
    vp = await found.validate({ amount: "1.0", options: op });
    expect(vp.valid).toBeTruthy();
    expect(vp.params.amount).toEqual("1.0");
  });

  let qr: Awaited<ReturnType<typeof found.quote>>;
  it("Should fetch a quote given the validated parameters", async function () {
    if (!vp.valid) throw new Error("Invalid transfer params used");
    qr = await found.quote(vp.params);
    if (!qr.success) throw new Error("Failed to fetch quote");

    expect(qr.params.amount).toEqual("1.0");

    const srcAddy = canonicalAddress(qr.sourceToken.token);
    expect(srcAddy).toEqual(SOL_TOKEN);

    const dstAddy = canonicalAddress(qr.destinationToken.token);
    expect(dstAddy).toEqual(SEPOLIA_TOKEN);

    // No fees or other fields
    expect(Object.keys(qr)).toEqual([
      "success",
      "params",
      "sourceToken",
      "destinationToken",
      "relayFee",
      "destinationNativeGas",
    ]);
  });
});

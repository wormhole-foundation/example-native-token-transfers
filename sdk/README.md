# NTT TypeScript SDK

The NTT TypeScript SDK is is a collection of packages that provide a simple interface for interacting with NTT contracts. The `@wormhole-foundation/sdk-route-ntt` package provides a Wormhole SDK `Route` for NTT, meant to be used with the [Router](https://github.com/wormhole-foundation/connect-sdk/blob/main/examples/src/router.ts) in the Wormhole SDK.

## Building

From this directory, install package dependencies and build contract dependencies

```bash
npm install
npm run build:deps
```

## Installation

```bash
npm install @wormhole-foundation/sdk-definitions-ntt
npm install @wormhole-foundation/sdk-evm-ntt
npm install @wormhole-foundation/sdk-solana-ntt
npm install @wormhole-foundation/sdk-route-ntt
```

## Usage

See [here](examples/src/route.ts) for an example of how to use this Route. Also see the demo [here](https://github.com/wormhole-foundation/demo-ntt-ts-sdk) for testing a NTT deployment.

## Usage

For an example of how to use this Route, please refer to the [example script](examples/src/route.ts). Additionally, you can test an NTT deployment by following the demo available [here](https://github.com/wormhole-foundation/demo-ntt-ts-sdk).
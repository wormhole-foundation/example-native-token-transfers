#!/usr/bin/env bun
import yargs from "yargs";
import { $ } from "bun";
import { hideBin } from "yargs/helpers";

type Network = "mainnet" | "testnet" | "devnet";

// TODO: grab this from sdkv2
export function assertNetwork(n: string): asserts n is Network {
    if (n !== "mainnet" && n !== "testnet" && n !== "devnet") {
        throw Error(`Unknown network: ${n}`);
    }
}

export const NETWORK_OPTIONS = {
    alias: "n",
    describe: "Network",
    choices: ["mainnet", "testnet", "devnet"],
    demandOption: true,
} as const;

yargs(hideBin(process.argv))
    .scriptName("ntt")
    .command(
        "solana",
        "Solana commands",
        (yargs) => {
            yargs
                .command(
                    "deploy",
                    "deploy the solana program",
                    (yargs) => yargs.option("network", NETWORK_OPTIONS),
                    (argv) => {
                        throw new Error("Not implemented");
                    })
                .command(
                    "upgrade",
                    "upgrade the solana program",
                    (yargs) => yargs
                        .option("network", NETWORK_OPTIONS)
                        .option("dir", {
                            alias: "d",
                            describe: "Path to the solana workspace",
                            default: ".",
                            demandOption: false,
                            type: "string",
                        })
                        .option("keypair", {
                            alias: "k",
                            describe: "Path to the keypair",
                            demandOption: true,
                            type: "string",
                        }),
                    async (argv) => {
                        // TODO: the hardcoded stuff should be factored out once
                        // we support other networks and programs
                        // TODO: currently the keypair is the upgrade authority. we should support governance program too
                        const network = argv.network;
                        const keypair = argv.keypair;
                        const dir = argv.dir;
                        const objectFile = "example_native_token_transfers.so";
                        const programId = "nttiK1SepaQt6sZ4WGW5whvc9tEnGXGxuKeptcQPCcS";
                        assertNetwork(network);
                        await $`cargo build-sbf --manifest-path=${dir}/Cargo.toml --no-default-features --features "${cargoNetworkFeature(network)}"`
                        await $`solana program deploy --program-id ${programId} ${dir}/target/deploy/${objectFile} --keypair ${keypair} -u ${solanaMoniker(network)}`
                    })
                .demandCommand()
        }
    )
    .help()
    .strict()
    .demandCommand()
    .parse();

function cargoNetworkFeature(network: Network): string {
    switch (network) {
        case "mainnet":
            return "mainnet";
        case "testnet":
            return "solana-devnet";
        case "devnet":
            return "tilt-devnet";
    }
}


function solanaMoniker(network: Network): string {
    switch (network) {
        case "mainnet":
            return "m";
        case "testnet":
            return "d";
        case "devnet":
            return "l";
    }
}

import solana from "@wormhole-foundation/sdk/platforms/solana";
import * as myEvmSigner from "./evmsigner.js";
import { ChainContext, Wormhole, chainToPlatform, type Chain, type ChainAddress, type Network, type Signer } from "@wormhole-foundation/sdk";

export type SignerType = "privateKey" | "ledger";

export type SignerSource = {
    type: SignerType;
    source: string;
};

// TODO: copied these from the examples. do they exist in the sdk?
export interface SignerStuff<N extends Network, C extends Chain> {
    chain: ChainContext<N, C>;
    signer: Signer<N, C>;
    address: ChainAddress<C>;
    source: SignerSource;
}

// arguments to pass to `forge`
export function forgeSignerArgs(
    source: SignerSource,
): string {
    let signerArgs
    switch (source.type) {
        case "privateKey":
            signerArgs = `--private-key ${source.source}`;
            break;
        case "ledger":
            signerArgs = `--ledger --mnemonic-derivation-paths "${source.source}"`;
            break;
        default:
            throw new Error("Unsupported signer type");
    }
    return signerArgs;
}

export async function getSigner<N extends Network, C extends Chain>(
    chain: ChainContext<N, C>,
    type: SignerType,
    source?: string
): Promise<SignerStuff<N, C>> {
    let signer: Signer;
    const platform = chainToPlatform(chain.chain);
    switch (platform) {
        case "Solana":
            switch (type) {
                case "privateKey":
                    source = source ?? process.env.SOLANA_PRIVATE_KEY;
                    if (source === undefined) {
                        throw new Error("SOLANA_PRIVATE_KEY env var not set");
                    }
                    signer = await solana.getSigner(
                        await chain.getRpc(),
                        source,
                        { debug: false }
                    );
                    break;
                case "ledger":
                    throw new Error("Ledger not yet supported on Solana");
                default:
                    throw new Error("Unsupported signer type");
            }
            break;
        case "Evm":
            switch (type) {
                case "privateKey":
                    source = source ?? process.env.ETH_PRIVATE_KEY;
                    if (source === undefined) {
                        throw new Error("ETH_PRIVATE_KEY env var not set");
                    }
                    signer = await myEvmSigner.getEvmSigner(
                        await chain.getRpc(),
                        source,
                        { debug: true }
                    );
                    break;
                case "ledger":
                    throw new Error("Ledger not yet supported on Evm");
                default:
                    throw new Error("Unsupported signer type");
            }
            break;
        default:
            throw new Error("Unrecognized platform: " + platform);
    }

    return {
        chain,
        signer: signer as Signer<N, C>,
        address: Wormhole.chainAddress(chain.chain, signer.address()),
        source: { type, source }
    };
}

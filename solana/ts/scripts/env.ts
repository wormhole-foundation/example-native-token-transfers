import {
  Connection,
  Keypair,
  Commitment,
} from "@solana/web3.js";
import { ChainId } from "@certusone/wormhole-sdk";
import { SolanaLedgerSigner } from "@xlabs-xyz/ledger-signer-solana";
import { Chain, chainIdToChain, chains } from "@wormhole-foundation/sdk-base";

if (!process.env.LEDGER_DERIVATION_PATH) {
  throw new Error("LEDGER_DERIVATION_PATH is not set");
}

const derivationPath = process.env.LEDGER_DERIVATION_PATH! as string;

let signer
export async function getSigner(): Promise<SolanaLedgerSigner> {
  if (!signer) {
    signer = await SolanaLedgerSigner.create(derivationPath)
  }

  return signer;
}

export function getEnv(key: string): string {
  if (!process.env[key]) {
    throw new Error(`${key} not found on environment`);
  }

  return process.env[key]!;
}

export const rpcUrl = process.env.SOLANA_RPC_URL || "https://api.devnet.solana.com";

export const connectionCommitmentLevel = (process.env.SOLANA_COMMITMENT || "confirmed") as Commitment;

export const connection = new Connection(rpcUrl, connectionCommitmentLevel);

export type NttDeployment = {
  chainId: ChainId;
  chainName: string;
  managerAddress: string;
  transceiverAddress: string;
  tokenDecimals: number;
  limit: number;
};

// TODO: read this data from config files similarly to the evm scripts
export const evmNttDeployments: NttDeployment[] = [
  {
    chainId: 10002,
    chainName: "ethereum",
    managerAddress: "0xB231aD95f2301bc82eA44c515001F0F746D637e0",
    transceiverAddress: "0x1fDC902e30b188FD2BA976B421Cb179943F57896",
    tokenDecimals: 18,
    limit: 100000000000000,
  },
  {
    chainId: 10003,
    chainName: "arbitrum",
    managerAddress: "0xEec94CD3083e067398256a79CcA7e740C5c8ef81",
    transceiverAddress: "0x0E24D17D7467467b39Bf64A9DFf88776Bd6c74d7",
    tokenDecimals: 18,
    limit: 100000000000000,
  },
  {
    chainId: 10004,
    chainName: "base",
    managerAddress: "0xB03b030b2f5B40819Df76467d67eD1C85Ff66fAD",
    transceiverAddress: "0x1e072169541f1171e427Aa44B5fd8924BEE71b0e",
    tokenDecimals: 18,
    limit: 100000000000000,
  },
  {
    chainId: 10005,
    chainName: "optimism",
    managerAddress: "0x7f430D4e7939D994C0955A01FC75D9DE33F12D11",
    transceiverAddress: "0x41265eb2863bf0238081F6AeefeF73549C82C3DD",
    tokenDecimals: 18,
    limit: 100000000000000,
  },
];

interface PeerQuotes {
  // Specified in Gwei per Eth units.
  maxGasDropoffEth: string,
  // The base price 10^-6 dollars.
  basePriceUsd: string,
  // Specified in 10^-6 dollars
  nativePriceUsd: string,
  // Specified in Gwei units.
  gasPriceGwei: string,
}

export const peerQuotes: Partial<Record<Chain, PeerQuotes>> = {
  [chainIdToChain(10002)]: {
    maxGasDropoffEth: "0",
    basePriceUsd: "5000000",
    nativePriceUsd: "3500000000",
    gasPriceGwei: "50",
  },
  [chainIdToChain(10003)]: {
    maxGasDropoffEth: "0",
    basePriceUsd: "5000000",
    nativePriceUsd: "3500000000",
    gasPriceGwei: "50",
  },
  [chainIdToChain(10004)]: {
    maxGasDropoffEth: "0",
    basePriceUsd: "5000000",
    nativePriceUsd: "3500000000",
    gasPriceGwei: "50",
  },
  [chainIdToChain(10005)]: {
    maxGasDropoffEth: "0",
    basePriceUsd: "5000000",
    nativePriceUsd: "3500000000",
    gasPriceGwei: "50",
  },
};

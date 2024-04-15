import {
  Connection,
  Keypair,
  Commitment,
} from "@solana/web3.js";
import { ChainId } from "@certusone/wormhole-sdk";
import { SolanaLedgerSigner } from "@xlabs-xyz/ledger-signer-solana";
import { Chain, chainIdToChain } from "@wormhole-foundation/sdk-base";

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

export type ManagersRegisteredPerChain = {
  chainId: ChainId;
  supportedManagers: {
    programId: string;
    gasCost: number;
    wormholeTransceiverIndex;
    isSupported: boolean;
  }[]
}[];

// TODO: read this data from config files similarly to the evm scripts
export const managerRegistrations = [
  {
    tokenAddress: "EetppHswYvV1jjRWoQKC1hejdeBDHR9NNzNtCyRQfrrQ",
    supportedManagers: [
      {
        programId: "NTtAaoDJhkeHeaVUHnyhwbPNAN6WgBpHkHBTc6d7vLK",
        gasCost: 400000,
        wormholeTransceiverIndex: 0,
        isSupported: true,
      },
    ],
  }
]

export const evmNttDeployments: NttDeployment[] = [
  {
    chainId: 10002,
    chainName: "ethereum",
    managerAddress: "0x06413c42e913327Bc9a08B7C1E362BAE7C0b9598",
    transceiverAddress: "0x649fF7B32C2DE771043ea105c4aAb2D724497238",
    tokenDecimals: 18,
    limit: 100000000000000,
  },
  {
    chainId: 10003,
    chainName: "arbitrum",
    managerAddress: "0xCeC6FB4F352bf3DC2b95E1c41831E4D2DBF9a35D",
    transceiverAddress: "0xfA42603152E4f133F5F3DA610CDa91dF5821d8bc",
    tokenDecimals: 18,
    limit: 100000000000000,
  },
  {
    chainId: 10004,
    chainName: "base",
    managerAddress: "0x8b9E328bE1b1Bc7501B413d04EBF7479B110775c",
    transceiverAddress: "0x149987472333cD48ac6D28293A338a1EEa6Be7EE",
    tokenDecimals: 18,
    limit: 100000000000000,
  },
  {
    chainId: 10005,
    chainName: "optimism",
    managerAddress: "0x27F9Fdd3eaD5aA9A5D827Ca860Be28442A1e7582",
    transceiverAddress: "0xeCF0496DE01e9Aa4ADB50ae56dB550f52003bdB7",
    tokenDecimals: 18,
    limit: 100000000000000,
  },
];

export interface PeerQuotes {
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

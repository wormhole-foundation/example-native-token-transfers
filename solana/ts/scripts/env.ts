import { BN } from '@coral-xyz/anchor'
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
    wormholeTransceiverIndex: number;
    isSupported: boolean;
  }[]
}[];

// TODO: read this data from config files similarly to the evm scripts
export const managerRegistrations = [
  {
    tokenAddress: "85VBFQZC9TZkfaptBWjvUw7YbZjy52A6mjtPGjstQAmQ",
    supportedManagers: [
      {
        programId: "NTtAaoDJhkeHeaVUHnyhwbPNAN6WgBpHkHBTc6d7vLK",
        gasCost: 400_000,
        wormholeTransceiverIndex: 0,
        isSupported: true,
      },
    ],
  }
]

export const outboundLimit = new BN(10_000_000);

export const evmNttDeployments: NttDeployment[] = [
  {
    chainId: 2,
    chainName: "ethereum",
    managerAddress: "0xc072B1AEf336eDde59A049699Ef4e8Fa9D594A48",
    transceiverAddress: "0xDb55492d7190D1baE8ACbE03911C4E3E7426870c",
    tokenDecimals: 18,
    limit: 4_200_000 * 10**6,
  },
  {
    chainId: 23,
    chainName: "arbitrum",
    managerAddress: "0x5333d0AcA64a450Add6FeF76D6D1375F726CB484",
    transceiverAddress: "0xD1a8AB69e00266e8B791a15BC47514153A5045a6",
    tokenDecimals: 18,
    limit: 1_300_000 * 10**6,
  },
  {
    chainId: 24,
    chainName: "optimism",
    managerAddress: "0x1a4F1a790f23Ffb9772966cB6F36dCd658033e13",
    transceiverAddress: "0x9bD8b7b527CA4e6738cBDaBdF51C22466756073d",
    tokenDecimals: 18,
    limit: 100_000 * 10**6,
  },
  {
    chainId: 30,
    chainName: "base",
    managerAddress: "0x5333d0AcA64a450Add6FeF76D6D1375F726CB484",
    transceiverAddress: "0xD1a8AB69e00266e8B791a15BC47514153A5045a6",
    tokenDecimals: 18,
    limit: 100_000 * 10**6,
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
  [chainIdToChain(2)]: {
    maxGasDropoffEth: "0",
    basePriceUsd: "500000",
    nativePriceUsd: "3500000000",
    gasPriceGwei: "25",
  },
  [chainIdToChain(23)]: {
    maxGasDropoffEth: "0",
    basePriceUsd: "500000",
    nativePriceUsd: "3500000000",
    gasPriceGwei: "25",
  },
  [chainIdToChain(24)]: {
    maxGasDropoffEth: "0",
    basePriceUsd: "500000",
    nativePriceUsd: "3500000000",
    gasPriceGwei: "25",
  },
  [chainIdToChain(30)]: {
    maxGasDropoffEth: "0",
    basePriceUsd: "500000",
    nativePriceUsd: "3500000000",
    gasPriceGwei: "25",
  },
};

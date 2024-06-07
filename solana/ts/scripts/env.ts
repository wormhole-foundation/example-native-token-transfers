import fs from "fs";
import { Connection, Commitment, Keypair, Transaction } from "@solana/web3.js";
import { ChainId, sign } from "@certusone/wormhole-sdk";
import { SolanaLedgerSigner } from "@xlabs-xyz/ledger-signer-solana";
import { Chain } from "@wormhole-foundation/sdk-base";
import { bs58 } from "@coral-xyz/anchor/dist/cjs/utils/bytes";
import nacl from "tweetnacl";

if (!process.env.ENV) {
  throw new Error("ENV not set");
}

const env = process.env.ENV;

export interface SolanaSigner {
  getAddress(): Promise<Buffer>;
  signMessage(message: Buffer): Promise<Buffer>;
  signTransaction(transaction: Buffer): Promise<Buffer>;
}

export class SolanaLocalSigner implements SolanaSigner {
  readonly keypair: Keypair;
  constructor(private privateKey: string) {
    this.keypair = Keypair.fromSecretKey(bs58.decode(this.privateKey));
  }

  async getAddress(): Promise<Buffer> {
    return this.keypair.publicKey.toBuffer();
  }

  async signMessage(message: Buffer): Promise<Buffer> {
    return Buffer.from(
      nacl.sign.detached(new Uint8Array(message), this.keypair.secretKey)
    );
  }

  async signTransaction(transaction: Buffer): Promise<Buffer> {
    const tx = Transaction.from(transaction);
    tx.sign(this.keypair);
    return tx.serialize();
  }
}

let signer;
export async function getSigner(): Promise<SolanaSigner> {
  if (signer) return signer;

  if (process.env.LEDGER_DERIVATION_PATH) {
    signer = await SolanaLedgerSigner.create(
      process.env.LEDGER_DERIVATION_PATH!
    );
  }

  if (process.env.SOLANA_PRIVATE_KEY) {
    signer = new SolanaLocalSigner(process.env.SOLANA_PRIVATE_KEY!);
  }

  if (!signer)
    throw new Error(
      "Either LEDGER_DERIVATION_PATH or SOLANA_PRIVATE_KEY must be set"
    );

  return signer;
}

export function getEnv(key: string): string {
  if (!process.env[key]) {
    throw new Error(`${key} not found on environment`);
  }

  return process.env[key]!;
}

export const rpcUrl =
  process.env.SOLANA_RPC_URL || "https://api.devnet.solana.com";

export const connectionCommitmentLevel = (process.env.SOLANA_COMMITMENT ||
  "confirmed") as Commitment;

export const connection = new Connection(rpcUrl, connectionCommitmentLevel);

export type NttDeployment = {
  chainId: ChainId;
  managerAddress: string;
  transceiverAddress: string;
  tokenDecimals: number;
  limit: number;
};

export type QuoterManagerRegistrations = {
  programId: string;
  tokenAddress: string;
  gasCost: number;
  wormholeTransceiverIndex: number;
  isSupported: boolean;
}[];

export type QuoterPeerQuotes = Partial<Record<Chain, QuoterPeerQuote>>;
export interface QuoterPeerQuote {
  // Specified in Gwei per Eth units.
  maxGasDropoffEth: string;
  // The base price 10^-6 dollars.
  basePriceUsd: string;
  // Specified in 10^-6 dollars
  nativePriceUsd: string;
  // Specified in Gwei units.
  gasPriceGwei: string;
}

export type QuoterConfig = {
  feeRecipient: string;
  assistant: string;
  solPriceUsd: number;
  peerQuotes: QuoterPeerQuotes;
  managerRegistrations: QuoterManagerRegistrations;
};

export type NttConfig = {
  outboundLimit: string;
  mode: "locking" | "burning";
};

export type Programs = {
  mintProgramId: string;
  nttProgramId: string;
  wormholeProgramId: string;
  quoterProgramId: string;
  governanceProgramId: string;
};

export type GovernanceVaa = {
  vaa: string;
};

export function getEvmNttDeployments(): NttDeployment[] {
  return loadScriptConfig("evm-peers");
}

export function getQuoterConfiguration(): QuoterConfig {
  return loadScriptConfig("quoter");
}

export function getNttConfiguration(): NttConfig {
  return loadScriptConfig("ntt");
}

export function getProgramAddresses(): Programs {
  return loadScriptConfig("programs");
}

export function getGovernanceVaa(): GovernanceVaa {
  return loadScriptConfig("governance-vaa");
}

export function loadScriptConfig(filename: string): any {
  const configFile = fs.readFileSync(
    `./ts/scripts/config/${env}/${filename}.json`
  );
  const config = JSON.parse(configFile.toString());
  if (!config) {
    throw Error("Failed to pull config file!");
  }
  return config;
}

export const guardianKey = getEnv("GUARDIAN_KEY");

import {
  Connection,
  Keypair,
  Commitment,
} from "@solana/web3.js";
import { ChainId } from "@certusone/wormhole-sdk";

const deployerSecretKey = process.env.SOLANA_DEPLOYER_SECRET_KEY;
if (!deployerSecretKey) {
  throw new Error("SOLANA_DEPLOYER_SECRET_KEY is not set");
}

export const deployerKeypair = Keypair.fromSecretKey(new Uint8Array(JSON.parse(deployerSecretKey)));

export const rpcUrl = process.env.SOLANA_RPC_URL || "https://api.devnet.solana.com";

export const connectionCommitmentLevel = (process.env.SOLANA_COMMITMENT || "confirmed") as Commitment;

export const connection = new Connection(rpcUrl, connectionCommitmentLevel);

export const mintRecipientAddress = process.env.MINT_RECIPIENT_ADDRESS;

export const mintAddress = process.env.MINT_ADDRESS;

export const wormholeProgramId = process.env.WORMHOLE_PROGRAM_ID;

export const nttProgramId = process.env.NTT_PROGRAM_ID;

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
    managerAddress: "0x47ac63a0540189d1A3d1445A8d00D625De836032",
    transceiverAddress: "0x30BF30344dB294164B2D05633339117F8ADA0153",
    tokenDecimals: 18,
    limit: 1000000,
  },
  {
    chainId: 10003,
    chainName: "arbitrum",
    managerAddress: "0x9084F113Dc5BACa71D80A9ff9BCed27051477B8e",
    transceiverAddress: "0x13C686745Ed17c648EA9748D7e56AfAE968582D9",
    tokenDecimals: 18,
    limit: 1000000,
  },
  {
    chainId: 10004,
    chainName: "base",
    managerAddress: "0x39dF42b92Ac2c15Ad2744c0C4Ba8Ff0AE7589F72",
    transceiverAddress: "0x67CA88E017c7B16bEEcbd30A1800733498845ac5",
    tokenDecimals: 18,
    limit: 1000000,
  },
  {
    chainId: 10005,
    chainName: "optimism",
    managerAddress: "0x9704863D8C4ACC733257f34Fd6c703b60B958F6B",
    transceiverAddress: "0x72f7Be5f83713354C4DF995327d4E9E6103d3582",
    tokenDecimals: 18,
    limit: 1000000,
  },
];
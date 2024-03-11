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
    managerAddress: "0x24c7E23e3A97cD2F04c9EB9F354bb7f3B31d2d1A",
    transceiverAddress: "0xC5bf11aB6aE525FFCA02e2af7F6704CDcECec2eA",
    tokenDecimals: 18,
    limit: 1000000,
  },
  {
    chainId: 10003,
    chainName: "arbitrum",
    managerAddress: "0xaBFa6Ab8dD4d4166b8fea7f84C1458BEf92F3a61",
    transceiverAddress: "0xC9a478f97ad763052AD4F00c4d7fC5d187DFFb1B",
    tokenDecimals: 18,
    limit: 1000000,
  },
  {
    chainId: 10004,
    chainName: "base",
    managerAddress: "0x838a95B6a3E06B6f11C437e22f3C7561a6ec40F1",
    transceiverAddress: "0xc3a1248e9bdC1EEF81d16b2AD1594764cBd9307a",
    tokenDecimals: 18,
    limit: 1000000,
  },
  {
    chainId: 10005,
    chainName: "optimism",
    managerAddress: "0x605dE5E0880Cfd6Ffc61aF9585CBAB3946594A3D",
    transceiverAddress: "0x5a76440b725909000697E0f72646adf1a492DF8B",
    tokenDecimals: 18,
    limit: 1000000,
  },
];
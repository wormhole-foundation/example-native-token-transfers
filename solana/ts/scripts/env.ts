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
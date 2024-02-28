import { ChainId } from "@certusone/wormhole-sdk";
import { ethers } from "ethers";
import fs from "fs";

export type ChainInfo = {
  evmNetworkId: number;
  chainId: ChainId;
  rpc: string;
  wormholeAddress: string;
};

export type Deployment = {
  chainId: ChainId;
  address: string;
};


const DEFAULT_ENV = "testnet";

export let env = "";
let lastRunOverride: boolean | undefined;

export function init(overrides: { lastRunOverride?: boolean } = {}): string {
  env = get_env_var("ENV");
  if (!env) {
    console.log(
      "No environment was specified, using default environment files"
    );
    env = DEFAULT_ENV;
  }
  lastRunOverride = overrides?.lastRunOverride;

  require("dotenv").config({
    path: `./ts-scripts/.env${env != DEFAULT_ENV ? "." + env : ""}`,
  });
  return env;
}

function get_env_var(env: string): string {
  const v = process.env[env];
  return v || "";
}

export function loadScriptConfig(processName: string): any {
  const configFile = fs.readFileSync(
    `./ts-scripts/config/${env}/scriptConfigs/${processName}.json`
  );
  const config = JSON.parse(configFile.toString());
  if (!config) {
    throw Error("Failed to pull config file!");
  }
  return config;
}

export function loadContracts<T>() {
  const contractsFile = fs.readFileSync(
    `./ts-scripts/config/${env}/contracts.json`
  );

  if (!contractsFile) {
    throw Error("Failed to find contracts file for this process!");
  }

  // NOTE: We assume that the contracts.json file is correctly formed...
  return JSON.parse(contractsFile.toString()) as T;
}

export function loadOperatingChains(): ChainInfo[] {
  const allChains = loadChains();
  let operatingChains: number[] | null = null;

  const chainFile = fs.readFileSync(`./ts-scripts/config/${env}/chains.json`);
  const chains = JSON.parse(chainFile.toString());
  if (chains.operatingChains) {
    operatingChains = chains.operatingChains;
  }
  if (!operatingChains) {
    return allChains;
  }

  const output: ChainInfo[] = [];
  operatingChains.forEach((x: number) => {
    const item = allChains.find((y) => {
      return x == y.chainId;
    });
    if (item) {
      output.push(item);
    }
  });

  return output;
}

export function loadChains(): ChainInfo[] {
  const chainFile = fs.readFileSync(`./ts-scripts/config/${env}/chains.json`);
  const chains = JSON.parse(chainFile.toString());
  if (!chains.chains) {
    throw Error("Failed to pull chain config file!");
  }
  return chains.chains;
}

export function getChain(chain: ChainId): ChainInfo {
  const chains = loadChains();
  const output = chains.find((x) => x.chainId == chain);
  if (!output) {
    throw Error("bad chain ID");
  }

  return output;
}

export function loadPrivateKey(): string {
  const privateKey = get_env_var("WALLET_KEY");
  if (!privateKey) {
    throw Error("Failed to find private key for this process!");
  }
  return privateKey;
}

export function loadGuardianSetIndex(): number {
  const chainFile = fs.readFileSync(`./ts-scripts/config/${env}/chains.json`);
  const chains = JSON.parse(chainFile.toString());
  if (chains.guardianSetIndex == undefined) {
    throw Error("Failed to pull guardian set index from the chains file!");
  }
  return chains.guardianSetIndex;
}

export function writeOutputFiles(output: any, processName: string) {
  fs.mkdirSync(`./ts-scripts/output/${env}/${processName}`, {
    recursive: true,
  });
  fs.writeFileSync(
    `./ts-scripts/output/${env}/${processName}/lastrun.json`,
    JSON.stringify(output),
    { flag: "w" }
  );
  fs.writeFileSync(
    `./ts-scripts/output/${env}/${processName}/${Date.now()}.json`,
    JSON.stringify(output),
    { flag: "w" }
  );
}

export async function getSigner(chain: ChainInfo): Promise<ethers.Signer> {
  const provider = getProvider(chain);
  const privateKey = loadPrivateKey();

  if (privateKey === "ledger") {
    console.log("ledger");
    if (process.env.LEDGER_BIP32_PATH === undefined) {
      throw new Error(`Missing BIP32 derivation path.
With ledger devices the path needs to be specified in env var 'LEDGER_BIP32_PATH'.`);
    }
    const { LedgerSigner } = await import("@xlabs-xyz/ledger-signer");
    console.log("ledger2", process.env.LEDGER_BIP32_PATH)
    return LedgerSigner.create(provider, process.env.LEDGER_BIP32_PATH);
  }

  const signer = new ethers.Wallet(privateKey, provider);
  return signer;
}

export function getProvider(
  chain: ChainInfo
): ethers.providers.StaticJsonRpcProvider {
  const providerRpc = loadChains().find((x: any) => x.chainId == chain.chainId)?.rpc || "";

  if (!providerRpc) {
    throw new Error("Failed to find a provider RPC for chain " + chain.chainId);
  }

  let provider = new ethers.providers.StaticJsonRpcProvider(
    providerRpc,  
  );

  return provider;
}

import {
  Layout,
  CustomConversion,
  encoding,
} from "@wormhole-foundation/sdk-base";

import { PublicKey, PublicKeyInitData } from "@solana/web3.js";
import { BN } from "@coral-xyz/anchor";

const CHAIN_ID_BYTE_SIZE = 2;
export const chainIdToBeBytes = chainId => encoding.bignum.toBytes(chainId, CHAIN_ID_BYTE_SIZE);

export const BPF_LOADER_UPGRADEABLE_PROGRAM_ID =
  new PublicKey("BPFLoaderUpgradeab1e11111111111111111111111");

export function programDataAddress(programId: PublicKeyInitData) {
  return PublicKey.findProgramAddressSync(
      [new PublicKey(programId).toBytes()],
      BPF_LOADER_UPGRADEABLE_PROGRAM_ID,
  )[0];
}

export const pubKeyConversion = {
  to:  (encoded: Uint8Array) => new PublicKey(encoded),
  from: (decoded: PublicKey) => decoded.toBytes(),
} as const satisfies CustomConversion<Uint8Array, PublicKey>;

//neither anchor nor solana web3 have a built-in way to parse this, because ofc they don't
export const programDataLayout = [
  { name: "slot", binary: "uint", endianness: "little", size: 8 },
  { name: "upgradeAuthority", binary: "switch", idSize: 1, idTag: "isSome", layouts: [
      [[0, false], []],
      [[1, true], [{name: "value", binary: "bytes", size: 32, custom: pubKeyConversion}]],
    ],
  }
] as const satisfies Layout;

export const U64 = {
  MAX: new BN((2n**64n - 1n).toString()),
  to: (amount: number, unit: number) => {
    const ret = new BN(Math.round(amount * unit));
  
    if (ret.isNeg())
      throw new Error("Value negative");
  
    if (ret.bitLength() > 64)
      throw new Error("Value too large");  
  
    return ret;
  },
  from: (amount: BN, unit: number) => amount.toNumber() / unit,
};

type Seed = Uint8Array | string;
export function derivePda(
  seeds: Seed | readonly Seed[],
  programId: PublicKeyInitData
) {
  const toBytes = (s: string | Uint8Array) => typeof s === "string" ? encoding.bytes.encode(s) : s;
  return PublicKey.findProgramAddressSync(    
    Array.isArray(seeds) ? seeds.map(toBytes) : [toBytes(seeds as Seed)],
    new PublicKey(programId),
  )[0];
}
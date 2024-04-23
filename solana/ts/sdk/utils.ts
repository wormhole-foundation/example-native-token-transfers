import {
  Layout,
  CustomConversion,
  encoding,
} from "@wormhole-foundation/sdk-base";

import { AccountMeta, PublicKey, PublicKeyInitData, TransactionInstruction } from "@solana/web3.js";
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

// governance utils

export function serializeInstruction(ix: TransactionInstruction): Buffer {
    const programId = ix.programId.toBuffer();
    const accountsLen = Buffer.alloc(2);
    accountsLen.writeUInt16BE(ix.keys.length);
    const accounts = Buffer.concat(ix.keys.map((account) => {
        const isSigner = Buffer.alloc(1);
        isSigner.writeUInt8(account.isSigner ? 1 : 0);
        const isWritable = Buffer.alloc(1);
        isWritable.writeUInt8(account.isWritable ? 1 : 0);
        const pubkey = account.pubkey.toBuffer();
        return Buffer.concat([pubkey, isSigner, isWritable]);
    }))
    const dataLen = Buffer.alloc(2);
    dataLen.writeUInt16BE(ix.data.length);
    return Buffer.concat([programId, accountsLen, accounts, dataLen, ix.data]);
}

export function deserializeInstruction(data: Buffer): TransactionInstruction {
    let offset = 0;
    const programId = new PublicKey(data.subarray(offset, offset + 32));
    offset += 32;
    const accountsLen = data.readUInt16BE(offset);
    offset += 2;
    const keys: Array<AccountMeta> = [];
    for (let i = 0; i < accountsLen; i++) {
        const pubkey = new PublicKey(data.subarray(offset, offset + 32));
        offset += 32;
        const isSigner = data.readUInt8(offset) === 1;
        offset += 1;
        const isWritable = data.readUInt8(offset) === 1;
        offset += 1;
        keys.push({ pubkey, isSigner, isWritable });
    }
    const dataLen = data.readUInt16BE(offset);
    offset += 2;
    const instructionData = data.subarray(offset, offset + dataLen);
    return new TransactionInstruction({ keys, programId, data: instructionData });
}

export function appendGovernanceHeader(data: Buffer, governanceProgramId: PublicKey): Buffer {
    const module = Buffer.from("GeneralPurposeGovernance".padStart(32, "\0"));
    const action = Buffer.alloc(1);
    action.writeUInt8(2); // SolanaCall
    const chainId = Buffer.alloc(2);
    chainId.writeUInt16BE(1); // solana
    const programId = governanceProgramId.toBuffer();
    return Buffer.concat([module, action, chainId, programId, data]);
}

export function verifyGovernanceHeader(data: Buffer): [PublicKey, Buffer] {
    let offset = 0;
    const module = data.subarray(offset, offset + 32);
    offset += 32;
    const action = data.readUInt8(offset);
    offset += 1;
    const chainId = data.readUInt16BE(offset);
    offset += 2;
    const governanceProgramId = new PublicKey(data.subarray(offset, offset + 32));
    offset += 32;
    if (!module.equals(Buffer.from("GeneralPurposeGovernance".padStart(32, "\0")))) {
        throw new Error("Invalid module");
    }
    if (action !== 2) {
        throw new Error("Invalid action");
    }
    if (chainId !== 1) {
        throw new Error("Invalid chainId");
    }
    return [governanceProgramId, data.subarray(offset)];
}

// sentinel values used in governance
export const OWNER = new PublicKey(Buffer.from("owner".padEnd(32, "\0")));
export const PAYER = new PublicKey(Buffer.from("payer".padEnd(32, "\0")));

import { IdlAccounts, Program } from "@coral-xyz/anchor";
import { OmitGenerics, _1_0_0 } from "./anchor-idl/index.js";
import { Connection } from "@solana/web3.js";

export const IdlVersions = {
  "1.0.0": _1_0_0,
  default: _1_0_0,
} as const;
export type IdlVersion = keyof typeof IdlVersions;

export namespace NttBindings {
  export type NativeTokenTransfer =
    OmitGenerics<_1_0_0.RawExampleNativeTokenTransfers>;
  export type Quoter = OmitGenerics<_1_0_0.RawNttQuoter>;

  export type Config = IdlAccounts<NttBindings.NativeTokenTransfer>["config"];
  export type InboxItem =
    IdlAccounts<NttBindings.NativeTokenTransfer>["inboxItem"];
}

function loadIdlVersion(version: string) {
  if (!(version in IdlVersions))
    throw new Error(`Unknown IDL version: ${version}`);
  return IdlVersions[version as IdlVersion];
}

export const getNttProgram = (
  connection: Connection,
  address: string,
  version: string = "default"
) =>
  new Program<NttBindings.NativeTokenTransfer>(
    // @ts-ignore
    loadIdlVersion(version).idl.ntt,
    address,
    { connection }
  );

export const getQuoterProgram = (
  connection: Connection,
  address: string,
  version: string = "default"
) =>
  new Program<NttBindings.Quoter>(
    // @ts-ignore
    loadIdlVersion(version).idl.quoter,
    address,
    { connection }
  );

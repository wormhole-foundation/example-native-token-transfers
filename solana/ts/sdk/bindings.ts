import { IdlAccounts, Program } from "@coral-xyz/anchor";
import { Connection } from "@solana/web3.js";
import { _1_0_0, _2_0_0 } from "./anchor-idl/index.js";

export const IdlVersions = {
  "1.0.0": _1_0_0,
  "2.0.0": _2_0_0,
  default: _2_0_0,
} as const;
export type IdlVersion = keyof typeof IdlVersions;

export namespace NttBindings {
  export type NativeTokenTransfer<V extends IdlVersion> = V extends "1.0.0"
    ? _1_0_0.RawExampleNativeTokenTransfers
    : _2_0_0.RawExampleNativeTokenTransfers;

  export type Quoter<V extends IdlVersion> = V extends "1.0.0"
    ? _1_0_0.RawNttQuoter
    : _2_0_0.RawNttQuoter;

  type ProgramAccounts<V extends IdlVersion> = IdlAccounts<
    NttBindings.NativeTokenTransfer<V>
  >;

  export type Config<V extends IdlVersion = IdlVersion> =
    ProgramAccounts<V>["config"];
  export type InboxItem<V extends IdlVersion = IdlVersion> =
    ProgramAccounts<V>["inboxItem"];
}

function loadIdlVersion<const V extends IdlVersion>(
  version: V
): (typeof IdlVersions)[V] {
  if (!(version in IdlVersions))
    throw new Error(`Unknown IDL version: ${version}`);
  return IdlVersions[version];
}

export function getNttProgram<const V extends IdlVersion>(
  connection: Connection,
  address: string,
  version: V
): Program<NttBindings.NativeTokenTransfer<V>> {
  return new Program<NttBindings.NativeTokenTransfer<V>>(
    //@ts-ignore
    loadIdlVersion(version).idl.ntt,
    address,
    { connection }
  );
}

export function getQuoterProgram<const V extends IdlVersion>(
  connection: Connection,
  address: string,
  version: V
) {
  return new Program<NttBindings.Quoter<V>>(
    loadIdlVersion(version).idl.quoter,
    address,
    {
      connection,
    }
  );
}

import { IdlAccounts, Program } from "@coral-xyz/anchor";
import { Connection } from "@solana/web3.js";
import { _1_0_0, _2_0_0 } from "./anchor-idl/index.js";

export interface IdlBinding<V extends IdlVersion> {
  idl: {
    ntt: NttBindings.NativeTokenTransfer<V>;
    quoter: NttBindings.Quoter<V>;
  };
}

export const IdlVersions = {
  "1.0.0": _1_0_0,
  "2.0.0": _2_0_0,
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

  export type Config<V extends IdlVersion> = ProgramAccounts<V>["config"];
  export type InboxItem<V extends IdlVersion> = ProgramAccounts<V>["inboxItem"];
}

function loadIdlVersion<V extends IdlVersion>(version: V): IdlBinding<V> {
  if (!(version in IdlVersions))
    throw new Error(`Unknown IDL version: ${version}`);
  return IdlVersions[version] as unknown as IdlBinding<V>;
}

export function getNttProgram<V extends IdlVersion>(
  connection: Connection,
  address: string,
  version: V
): Program<NttBindings.NativeTokenTransfer<V>> {
  const {
    idl: { ntt },
  } = loadIdlVersion(version);
  return new Program<NttBindings.NativeTokenTransfer<V>>(ntt, address, {
    connection,
  });
}

export function getQuoterProgram<V extends IdlVersion>(
  connection: Connection,
  address: string,
  version: V
) {
  const {
    idl: { quoter },
  } = loadIdlVersion(version);
  return new Program<NttBindings.Quoter<V>>(quoter, address, {
    connection,
  });
}

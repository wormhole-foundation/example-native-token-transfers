import { IdlAccounts, Program } from "@coral-xyz/anchor";
import { Connection } from "@solana/web3.js";
import { OmitGenerics, _1_0_0, _2_0_0 } from "./anchor-idl/index.js";

export const IdlVersions = {
  "1.0.0": _1_0_0,
  "2.0.0": _2_0_0,
  default: _2_0_0,
} as const;
export type IdlVersion = keyof typeof IdlVersions;

export namespace NttBindings {
  export type NativeTokenTransfer<V extends IdlVersion = "default"> =
    V extends "1.0.0"
      ? OmitGenerics<_1_0_0.RawExampleNativeTokenTransfers>
      : OmitGenerics<_2_0_0.RawExampleNativeTokenTransfers>;
  export type Quoter<V extends IdlVersion = "default"> = V extends "1.0.0"
    ? OmitGenerics<_1_0_0.RawNttQuoter>
    : OmitGenerics<_2_0_0.RawNttQuoter>;

  export type Config<V extends IdlVersion = "default"> = IdlAccounts<
    NttBindings.NativeTokenTransfer<V>
  >["config"];

  export type InboxItem<V extends IdlVersion = "default"> = IdlAccounts<
    NttBindings.NativeTokenTransfer<V>
  >["inboxItem"];
}

function loadIdlVersion<V extends IdlVersion>(
  version: V
): (typeof IdlVersions)[V] {
  if (!(version in IdlVersions))
    throw new Error(`Unknown IDL version: ${version}`);
  return IdlVersions[version];
}

export const getNttProgram = (
  connection: Connection,
  address: string,
  version: IdlVersion = "default"
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
  version: IdlVersion = "default"
) =>
  new Program<NttBindings.Quoter<typeof version>>(
    loadIdlVersion(version).idl.quoter,
    address,
    {
      connection,
    }
  );

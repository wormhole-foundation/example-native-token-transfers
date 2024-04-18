import { IdlAccounts } from "@coral-xyz/anchor";
import { OmitGenerics, _1_0_0 } from "./anchor-idl/index.js";

export const IdlVersions = {
  "1.0.0": _1_0_0,
  default: _1_0_0,
} as const;
export type IdlVersion = keyof typeof IdlVersions;

export namespace NttBindings {
  export type NativeTokenTransfer =
    OmitGenerics<_1_0_0.RawExampleNativeTokenTransfers>;

  export type Config = IdlAccounts<NttBindings.NativeTokenTransfer>["config"];
  export type InboxItem =
    IdlAccounts<NttBindings.NativeTokenTransfer>["inboxItem"];
}

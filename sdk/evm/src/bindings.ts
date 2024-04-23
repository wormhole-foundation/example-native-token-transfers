import { Provider } from "ethers";

import { _0_1_0, _1_0_0 } from "./ethers-contracts/index.js";

export const AbiVersions = {
  "0.1.0": _0_1_0,
  "1.0.0": _1_0_0,
  default: _1_0_0,
} as const;
export type AbiVersion = keyof typeof AbiVersions;

export interface NttBindings {
  NttManager: NttManagerBindings;
  NttTransceiver: NttTransceiverBindings;
}

export namespace NttTransceiverBindings {
  // Note: this is hardcoded to 0.1.0 so we should be warned if there are changes
  // that would affect the interface
  export type NttTransceiver = ReturnType<typeof _0_1_0.NttTransceiver.connect>;
}

export interface NttTransceiverBindings {
  connect(
    address: string,
    provider: Provider
  ): NttTransceiverBindings.NttTransceiver;
}

export namespace NttManagerBindings {
  export type NttManager = ReturnType<typeof _0_1_0.NttManager.connect>;
}

export interface NttManagerBindings {
  connect(address: string, provider: Provider): NttManagerBindings.NttManager;
}

export function loadAbiVersion(version: string) {
  if (!(version in AbiVersions))
    throw new Error(`Unknown ABI version: ${version}`);
  return AbiVersions[version as AbiVersion];
}

import {
  Program,
} from "@coral-xyz/anchor";
import {
  PublicKey,
  type Connection,
} from "@solana/web3.js";
import { type WormholeGovernance as RawWormholeGovernance } from "../../target/types/wormhole_governance";
import IDL from "../../target/idl/example_native_token_transfers.json";

import { derivePda } from "./utils";

export * from "./utils/wormhole";

// This is a workaround for the fact that the anchor idl doesn't support generics
// yet. This type is used to remove the generics from the idl types.
type OmitGenerics<T> = {
  [P in keyof T]: T[P] extends Record<"generics", any>
    ? never
    : T[P] extends object
    ? OmitGenerics<T[P]>
    : T[P];
};

export type ExampleNativeTokenTransfers =
  OmitGenerics<RawWormholeGovernance>;

export const GOV_PROGRAM_IDS = [
  "NTTManager111111111111111111111111111111111",
  "NGoD1yTeq5KaURrZo7MnCTFzTA4g62ygakJCnzMLCfm",
  "NGoD1yTeq5KaURrZo7MnCTFzTA4g62ygakJCnzMLCfm",
] as const;

export type GovProgramId = (typeof GOV_PROGRAM_IDS)[number];

export class NTTGovernance {
  readonly program: Program<ExampleNativeTokenTransfers>;
  readonly wormholeId: PublicKey;

  constructor(
    connection: Connection,
    args: { programId: GovProgramId; }
  ) {
    // TODO: initialise a new Program here with a passed in Connection
    this.program = new Program(IDL as any, new PublicKey(args.programId), {
      connection,
    });
  }

  governanceAccountAddress () {
      return derivePda("governance", this.program.programId);
  }
}

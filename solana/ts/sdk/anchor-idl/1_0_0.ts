import { type ExampleNativeTokenTransfers } from "../../idl/1_0_0/ts/example_native_token_transfers.js";
import * as ntt from "../../idl/1_0_0/json/example_native_token_transfers.json";

import { type NttQuoter } from "../../idl/1_0_0/ts/ntt_quoter.js";
import * as quoter from "../../idl/1_0_0/json/ntt_quoter.json";

import { type WormholeGovernance } from "../../idl/1_0_0/ts/wormhole_governance.js";
import * as governance from "../../idl/1_0_0/json/wormhole_governance.json";

export namespace _1_0_0 {
  export const idl = { ntt, quoter, governance };

  export type RawExampleNativeTokenTransfers = ExampleNativeTokenTransfers;
  export type RawNttQuoter = NttQuoter;
  export type RawWormholeGovernance = WormholeGovernance;
}

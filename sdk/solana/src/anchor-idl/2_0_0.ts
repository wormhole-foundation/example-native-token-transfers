import ntt from "./2_0_0/example_native_token_transfers.json";
import quoter from "./2_0_0/ntt_quoter.json";
import governance from "./2_0_0/wormhole_governance.json";

import type { ExampleNativeTokenTransfers } from "./2_0_0/example_native_token_transfers.js";
import type { NttQuoter } from "./2_0_0/ntt_quoter.js";
import type { WormholeGovernance } from "./2_0_0/wormhole_governance.js";

export namespace _2_0_0 {
  export const idl = { ntt, quoter, governance };

  export type RawExampleNativeTokenTransfers = ExampleNativeTokenTransfers;
  export type RawNttQuoter = NttQuoter;
  export type RawWormholeGovernance = WormholeGovernance;
}

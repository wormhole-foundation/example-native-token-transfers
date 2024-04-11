import { registerPayloadTypes } from "@wormhole-foundation/sdk";
import { nttNamedPayloads } from "./layouts/index.js";

registerPayloadTypes("Ntt", nttNamedPayloads);

export * from "./ntt.js";

export * from "./layouts/index.js";
export type * from "./layouts/index.js";

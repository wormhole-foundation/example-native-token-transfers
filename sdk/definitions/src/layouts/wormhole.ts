import type {
  CustomConversion,
  CustomizableBytes,
  Layout,
  LayoutToType,
} from "@wormhole-foundation/sdk-base";
import {
  deserializeLayout,
  serializeLayout,
} from "@wormhole-foundation/sdk-base";
import { transceiverMessageLayout } from "./transceiver.js";

export type WormholeTransceiverMessage<
  MP extends CustomizableBytes = undefined
> = LayoutToType<ReturnType<typeof wormholeTransceiverMessageLayout<MP>>>;

export const wormholeTransceiverMessageLayout = <
  MP extends CustomizableBytes = undefined
>(
  nttManagerPayload?: MP
) =>
  transceiverMessageLayout(
    [0x99, 0x45, 0xff, 0x10],
    nttManagerPayload,
    optionalWormholeTransceiverPayloadConversion
  );

type OptionalWormholeTransceiverPayload = LayoutToType<
  typeof optionalWormholeTransceiverPayloadLayout
>;
const optionalWormholeTransceiverPayloadLayout = [
  { name: "version", binary: "uint", size: 2, custom: 1, omit: true },
  {
    name: "forSpecializedRelayer",
    binary: "uint",
    size: 1,
    custom: {
      to: (val: number) => val > 0,
      from: (val: boolean) => (val ? 1 : 0),
    },
  },
] as const satisfies Layout;
const optionalWormholeTransceiverPayloadConversion = {
  to: (encoded: Uint8Array) =>
    encoded.length === 0
      ? null
      : deserializeLayout(optionalWormholeTransceiverPayloadLayout, encoded),

  from: (value: OptionalWormholeTransceiverPayload | null): Uint8Array =>
    value === null
      ? new Uint8Array(0)
      : serializeLayout(optionalWormholeTransceiverPayloadLayout, value),
} as const satisfies CustomConversion<
  Uint8Array,
  OptionalWormholeTransceiverPayload | null
>;

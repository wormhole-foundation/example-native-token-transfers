import { Layout, LayoutToType } from "@wormhole-foundation/sdk-base";
import { layoutItems } from "@wormhole-foundation/sdk-definitions";
import { trimmedAmountItem } from "./amount.js";
import { prefixItem } from "./prefix.js";

export type NativeTokenTransfer = LayoutToType<
  typeof nativeTokenTransferLayout
>;
/** Describes binary layout for a native token transfer payload */
export const nativeTokenTransferLayout = [
  prefixItem([0x99, 0x4e, 0x54, 0x54]),
  { name: "trimmedAmount", ...trimmedAmountItem },
  { name: "sourceToken", ...layoutItems.universalAddressItem },
  { name: "recipientAddress", ...layoutItems.universalAddressItem },
  { name: "recipientChain", ...layoutItems.chainItem() },
] as const satisfies Layout;

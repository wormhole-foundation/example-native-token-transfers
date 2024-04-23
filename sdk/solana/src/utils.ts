import { PublicKey, PublicKeyInitData } from "@solana/web3.js";
import {
  Chain,
  ChainId,
  CustomConversion,
  Layout,
  encoding,
  keccak256,
  toChainId,
  ChainAddress,
} from "@wormhole-foundation/sdk-connect";
import { Ntt } from "@wormhole-foundation/sdk-definitions-ntt";
import BN from "bn.js";

export const BPF_LOADER_UPGRADEABLE_PROGRAM_ID = new PublicKey(
  "BPFLoaderUpgradeab1e11111111111111111111111"
);

export function programDataAddress(programId: PublicKeyInitData) {
  return PublicKey.findProgramAddressSync(
    [new PublicKey(programId).toBytes()],
    BPF_LOADER_UPGRADEABLE_PROGRAM_ID
  )[0];
}

export const pubKeyConversion = {
  to: (encoded: Uint8Array) => new PublicKey(encoded),
  from: (decoded: PublicKey) => decoded.toBytes(),
} as const satisfies CustomConversion<Uint8Array, PublicKey>;

//neither anchor nor solana web3 have a built-in way to parse this, because ofc they don't
export const programDataLayout = [
  { name: "slot", binary: "uint", endianness: "little", size: 8 },
  {
    name: "upgradeAuthority",
    binary: "switch",
    idSize: 1,
    idTag: "isSome",
    layouts: [
      [[0, false], []],
      [
        [1, true],
        [
          {
            name: "value",
            binary: "bytes",
            size: 32,
            custom: pubKeyConversion,
          },
        ],
      ],
    ],
  },
] as const satisfies Layout;

export const programVersionLayout = [
  { name: "length", binary: "uint", endianness: "little", size: 4 },
  { name: "version", binary: "bytes" },
] as const satisfies Layout;

export const U64 = {
  MAX: new BN((2n ** 64n - 1n).toString()),
  to: (amount: number, unit: number) => {
    const ret = new BN(Math.round(amount * unit));
    if (ret.isNeg()) throw new Error("Value negative");
    if (ret.bitLength() > 64) throw new Error("Value too large");
    return ret;
  },
  from: (amount: BN, unit: number) => amount.toNumber() / unit,
};

export interface TransferArgs {
  amount: bigint;
  recipient: ChainAddress;
  shouldQueue: boolean;
}

type Seed = Uint8Array | string;
export function derivePda(
  seeds: Seed | readonly Seed[],
  programId: PublicKeyInitData
) {
  const toBytes = (s: string | Uint8Array) =>
    typeof s === "string" ? encoding.bytes.encode(s) : s;
  return PublicKey.findProgramAddressSync(
    Array.isArray(seeds) ? seeds.map(toBytes) : [toBytes(seeds as Seed)],
    new PublicKey(programId)
  )[0];
}

const chainToBytes = (chain: Chain | ChainId) =>
  encoding.bignum.toBytes(toChainId(chain), 2);

export const nttAddresses = (programId: PublicKeyInitData) => {
  const configAccount = (): PublicKey => derivePda("config", programId);
  const emitterAccount = (): PublicKey => derivePda("emitter", programId);
  const inboxRateLimitAccount = (chain: Chain): PublicKey =>
    derivePda(["inbox_rate_limit", chainToBytes(chain)], programId);
  const inboxItemAccount = (chain: Chain, nttMessage: Ntt.Message): PublicKey =>
    derivePda(["inbox_item", Ntt.messageDigest(chain, nttMessage)], programId);
  const outboxRateLimitAccount = (): PublicKey =>
    derivePda("outbox_rate_limit", programId);
  const tokenAuthority = (): PublicKey =>
    derivePda("token_authority", programId);
  const peerAccount = (chain: Chain): PublicKey =>
    derivePda(["peer", chainToBytes(chain)], programId);
  const transceiverPeerAccount = (chain: Chain): PublicKey =>
    derivePda(["transceiver_peer", chainToBytes(chain)], programId);
  const registeredTransceiver = (transceiver: PublicKey): PublicKey =>
    derivePda(["registered_transceiver", transceiver.toBytes()], programId);
  const transceiverMessageAccount = (chain: Chain, id: Uint8Array): PublicKey =>
    derivePda(["transceiver_message", chainToBytes(chain), id], programId);
  const wormholeMessageAccount = (outboxItem: PublicKey): PublicKey =>
    derivePda(["message", outboxItem.toBytes()], programId);
  const sessionAuthority = (sender: PublicKey, args: TransferArgs): PublicKey =>
    derivePda(
      [
        "session_authority",
        sender.toBytes(),
        keccak256(
          encoding.bytes.concat(
            encoding.bignum.toBytes(args.amount, 8),
            chainToBytes(args.recipient.chain),
            args.recipient.address.toUniversalAddress().toUint8Array(),
            new Uint8Array([args.shouldQueue ? 1 : 0])
          )
        ),
      ],
      programId
    );

  return {
    configAccount,
    outboxRateLimitAccount,
    inboxRateLimitAccount,
    inboxItemAccount,
    sessionAuthority,
    tokenAuthority,
    emitterAccount,
    wormholeMessageAccount,
    peerAccount,
    transceiverPeerAccount,
    transceiverMessageAccount,
    registeredTransceiver,
  };
};

export const quoterAddresses = (programId: PublicKeyInitData) => {
  const instanceAccount = () => derivePda("instance", programId);
  const registeredNttAccount = (nttProgramId: PublicKey) =>
    derivePda(["registered_ntt", nttProgramId.toBytes()], programId);
  const relayRequestAccount = (outboxItem: PublicKey) =>
    derivePda(["relay_request", outboxItem.toBytes()], programId);
  const registeredChainAccount = (chain: Chain) =>
    derivePda(["registered_chain", chainToBytes(chain)], programId);
  return {
    relayRequestAccount,
    instanceAccount,
    registeredChainAccount,
    registeredNttAccount,
  };
};

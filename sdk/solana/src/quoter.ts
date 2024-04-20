import { BN, Program } from "@coral-xyz/anchor";
import {
  Connection,
  LAMPORTS_PER_SOL,
  PublicKey,
  SystemProgram,
} from "@solana/web3.js";
import { Chain, Contracts, toChainId } from "@wormhole-foundation/sdk";
import { Network } from "ethers";
import { IdlVersion, NttBindings, getQuoterProgram } from "./bindings.js";
import { U64 } from "./utils.js";

//constants that must match ntt-quoter lib.rs / implementation:
const EVM_GAS_COST = 250_000; // TODO: make sure this is right
const USD_UNIT = 1e6;
const WEI_PER_GWEI = 1e9;
const GWEI_PER_ETH = 1e9;
const SEED_PREFIX_INSTANCE = "instance";
const SEED_PREFIX_REGISTERED_CHAIN = "registered_chain";
const SEED_PREFIX_RELAY_REQUEST = "relay_request";

export class NttQuoter<N extends Network, C extends Chain> {
  program: Program<NttBindings.Quoter>;
  instance: PublicKey;

  constructor(
    readonly network: N,
    readonly chain: C,
    readonly connection: Connection,
    readonly contracts: Contracts & { quoter: string },
    readonly idlVersion: IdlVersion = "default"
  ) {
    if (!contracts.quoter) throw new Error("No quoter program found");

    this.program = getQuoterProgram(connection, contracts.quoter);

    this.instance = this.derivePda(Buffer.from(SEED_PREFIX_INSTANCE));
  }

  async isRelayEnabled(destination: Chain) {
    try {
      const { paused } = await this.getRegisteredChain(destination);
      return !paused;
    } catch (e: any) {
      if (e.message?.includes("Account does not exist")) {
        return false;
      }
      throw e;
    }
  }

  // TODO: will change with https://github.dev/wormhole-foundation/example-native-token-transfers/pull/319
  async calcRelayCost(chain: Chain) {
    const [chainData, instanceData, rentCost] = await Promise.all([
      this.getRegisteredChain(chain),
      this.getInstance(),
      this.program.provider.connection.getMinimumBalanceForRentExemption(
        this.program.account.relayRequest.size
      ),
    ]);

    if (chainData.nativePriceUsd === 0) {
      throw new Error("Native price is 0");
    }
    if (instanceData.solPriceUsd === 0) {
      throw new Error("SOL price is 0");
    }

    const totalNativeGasCostUsd =
      chainData.nativePriceUsd *
      ((chainData.gasPriceGwei * EVM_GAS_COST) / GWEI_PER_ETH);

    const totalCostSol =
      rentCost / LAMPORTS_PER_SOL +
      (chainData.basePriceUsd + totalNativeGasCostUsd) /
        instanceData.solPriceUsd;

    // Add 5% to account for possible price updates while the tx is in flight
    const cost = U64.to(totalCostSol * 1.05, LAMPORTS_PER_SOL);
    return cost;
  }

  async createRequestRelayInstruction(
    payer: PublicKey,
    outboxItem: PublicKey,
    chain: Chain,
    maxFee: BN
  ) {
    return this.program.methods
      .requestRelay({
        maxFee,
        gasDropoff: new BN(0),
      })
      .accounts({
        payer,
        instance: this.instance,
        registeredChain: this.registeredChainPda(toChainId(chain)),
        outboxItem,
        relayRequest: this.relayRequestPda(outboxItem),
        systemProgram: SystemProgram.programId,
      })
      .instruction();
  }

  async getInstance() {
    const data = await this.program.account.instance.fetch(this.instance);
    return {
      owner: data.owner,
      assistant: data.assistant,
      feeRecipient: data.feeRecipient,
      solPriceUsd: U64.from(data.solPrice, USD_UNIT),
    };
  }

  async getRegisteredChain(chain: Chain) {
    const data = await this.program.account.registeredChain.fetch(
      this.registeredChainPda(toChainId(chain))
    );

    return {
      paused: data.basePrice.eq(U64.MAX),
      maxGasDropoffEth: U64.from(data.maxGasDropoff, GWEI_PER_ETH),
      basePriceUsd: U64.from(data.basePrice, USD_UNIT),
      nativePriceUsd: U64.from(data.nativePrice, USD_UNIT),
      gasPriceGwei: U64.from(data.gasPrice, WEI_PER_GWEI),
    };
  }

  private registeredChainPda(chainId: number) {
    return this.derivePda([
      Buffer.from(SEED_PREFIX_REGISTERED_CHAIN),
      new BN(chainId).toBuffer("be", 2),
    ]);
  }

  private relayRequestPda(outboxItem: PublicKey) {
    return this.derivePda([
      Buffer.from(SEED_PREFIX_RELAY_REQUEST),
      outboxItem.toBytes(),
    ]);
  }

  private derivePda(seeds: Buffer | Array<Uint8Array | Buffer>): PublicKey {
    const seedsArray = seeds instanceof Buffer ? [seeds] : seeds;
    const [address] = PublicKey.findProgramAddressSync(
      seedsArray,
      this.program.programId
    );
    return address;
  }
}

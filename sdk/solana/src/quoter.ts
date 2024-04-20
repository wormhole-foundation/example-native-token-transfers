import { BN, Program } from "@coral-xyz/anchor";
import {
  Connection,
  LAMPORTS_PER_SOL,
  PublicKey,
  SystemProgram,
} from "@solana/web3.js";
import { Chain, Contracts, Network } from "@wormhole-foundation/sdk";
import { Ntt } from "@wormhole-foundation/sdk-definitions-ntt";
import { IdlVersion, NttBindings, getQuoterProgram } from "./bindings.js";
import { U64, quoterAddresses } from "./utils.js";

//constants that must match ntt-quoter lib.rs / implementation:
const EVM_GAS_COST = 250_000; // TODO: make sure this is right
const USD_UNIT = 1e6;
const WEI_PER_GWEI = 1e9;
const GWEI_PER_ETH = 1e9;

export class NttQuoter<N extends Network, C extends Chain> {
  program: Program<NttBindings.Quoter>;
  pdas: ReturnType<typeof quoterAddresses>;
  instance: PublicKey;

  constructor(
    readonly network: N,
    readonly chain: C,
    readonly connection: Connection,
    readonly contracts: Contracts & { ntt?: Ntt.Contracts },
    readonly idlVersion: IdlVersion = "default"
  ) {
    if (!contracts.ntt?.quoter) throw new Error("No quoter program found");
    this.program = getQuoterProgram(connection, contracts.ntt.quoter);
    this.pdas = quoterAddresses(this.program.programId);

    this.instance = this.pdas.instanceAccount();
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
    return BigInt(U64.to(totalCostSol * 1.05, LAMPORTS_PER_SOL).toString());
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
        registeredChain: this.pdas.registeredChainAccount(chain),
        outboxItem,
        relayRequest: this.pdas.relayRequestAccount(outboxItem),
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
      this.pdas.registeredChainAccount(chain)
    );

    return {
      paused: data.basePrice.eq(U64.MAX),
      maxGasDropoffEth: U64.from(data.maxGasDropoff, GWEI_PER_ETH),
      basePriceUsd: U64.from(data.basePrice, USD_UNIT),
      nativePriceUsd: U64.from(data.nativePrice, USD_UNIT),
      gasPriceGwei: U64.from(data.gasPrice, WEI_PER_GWEI),
    };
  }
}

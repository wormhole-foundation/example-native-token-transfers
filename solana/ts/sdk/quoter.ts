import { BN, Program } from "@coral-xyz/anchor";
import {
  Connection,
  LAMPORTS_PER_SOL,
  PublicKey,
  SystemProgram,
} from "@solana/web3.js";
import {
  Chain,
  Contracts,
  Network,
  amount,
  chainToPlatform,
} from "@wormhole-foundation/sdk";
import { Ntt } from "@wormhole-foundation/sdk-definitions-ntt";
import { IdlVersion, NttBindings, getQuoterProgram } from "./bindings.js";
import { U64, quoterAddresses } from "./utils.js";

//constants that must match ntt-quoter lib.rs / implementation:
const USD_UNIT = 1e6;
const WEI_PER_GWEI = 1e9;
const GWEI_PER_ETH = 1e9;

export class NttQuoter<N extends Network, C extends Chain> {
  program: Program<NttBindings.Quoter>;
  pdas: ReturnType<typeof quoterAddresses>;

  instance: PublicKey;
  nttProgramId: PublicKey;

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
    this.nttProgramId = new PublicKey(contracts.ntt.manager);
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

  /**
   * Estimate the cost of a relay request
   * @param chain The destination chain
   * @param gasDropoff The amount of native gas to end up with on the destination chain
   * @returns The estimated cost in lamports
   */
  async quoteDeliveryPrice(chain: Chain, gasDropoff?: bigint) {
    if (chainToPlatform(chain) !== "Evm")
      throw new Error("Only EVM chains are supported");

    // Convert to decimal number since we're multiplying other numbers
    const gasDropoffEth = amount.whole(
      amount.fromBaseUnits(gasDropoff ?? 0n, 18)
    );

    const [chainData, instanceData, nttData, rentCost] = await Promise.all([
      this.getRegisteredChain(chain),
      this.getInstance(),
      this.getRegisteredNtt(),
      this.program.provider.connection.getMinimumBalanceForRentExemption(
        this.program.account.relayRequest.size
      ),
    ]);

    if (chainData.nativePriceUsd === 0) throw new Error("Native price is 0");
    if (instanceData.solPriceUsd === 0) throw new Error("SOL price is 0");
    if (gasDropoffEth > chainData.maxGasDropoffEth)
      throw new Error("Requested gas dropoff exceeds allowed maximum");

    const totalNativeGasCostUsd =
      chainData.nativePriceUsd *
      (gasDropoffEth +
        (chainData.gasPriceGwei * nttData.gasCost) / GWEI_PER_ETH);

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
    nttProgramId: PublicKey,
    chain: Chain,
    maxFee: BN,
    gasDropoff: BN
  ) {
    return this.program.methods
      .requestRelay({ maxFee, gasDropoff })
      .accounts({
        payer,
        instance: this.instance,
        registeredChain: this.pdas.registeredChainAccount(chain),
        registeredNtt: this.pdas.registeredNttAccount(nttProgramId),
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

  async getRegisteredNtt() {
    const data = await this.program.account.registeredNtt.fetch(
      this.pdas.registeredNttAccount(this.nttProgramId)
    );
    return {
      gasCost: data.gasCost,
      wormholeTransceiverIndex: data.wormholeTransceiverIndex,
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

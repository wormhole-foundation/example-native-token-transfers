import {
  deserializeLayout,
  Chain,
  toChainId,
  encoding,
} from "@wormhole-foundation/sdk-base";
import {
  Connection,
  PublicKeyInitData,
  PublicKey,
  SystemProgram,
  LAMPORTS_PER_SOL,
} from "@solana/web3.js";
import { Program } from "@coral-xyz/anchor";
import { NttQuoter as Idl } from '../../target/types/ntt_quoter'
import IDL from "../../target/idl/ntt_quoter.json";
import { U64, programDataLayout, programDataAddress, chainIdToBeBytes, derivePda } from "./utils";

//constants that must match ntt-quoter lib.rs / implementation:
const EVM_GAS_COST = 250_000;
const USD_UNIT     = 1e6;
const WEI_PER_GWEI = 1e9;
const GWEI_PER_ETH = 1e9;
const SEED_PREFIX_INSTANCE         = "instance";
const SEED_PREFIX_REGISTERED_CHAIN = "registered_chain";
const SEED_PREFIX_RELAY_REQUEST    = "relay_request";

export class NttQuoter {
  readonly instance: PublicKey;
  private readonly program: Program<Idl>;
  
  constructor(connection: Connection, programId: PublicKeyInitData) {
    this.program  = new Program<Idl>(IDL as Idl, new PublicKey(programId), {connection});
    this.instance = derivePda([SEED_PREFIX_INSTANCE], this.program.programId);
  }

  // ---- user relevant functions ----

  async calcRelayCostInSol(chain: Chain, requestedGasDropoffEth: number) {
    const [chainData, instanceData, rentCost] = await Promise.all([
      this.getRegisteredChain(chain),
      this.getInstance(),
      this.program.provider.connection.getMinimumBalanceForRentExemption(
        this.program.account.relayRequest.size
      )
    ]);

    if (requestedGasDropoffEth > chainData.maxGasDropoffEth)
      throw new Error("Requested gas dropoff exceeds allowed maximum");

    const totalNativeGasCostUsd = chainData.nativePriceUsd *
      (requestedGasDropoffEth + chainData.gasPriceGwei * EVM_GAS_COST * GWEI_PER_ETH);

    const totalCostSol = rentCost +
      (chainData.basePriceUsd + totalNativeGasCostUsd) / instanceData.solPriceUsd;
    
    return totalCostSol;
  }

  async createRequestRelayInstruction(
    payer:         PublicKey,
    outboxItem:    PublicKey,
    chain:         Chain,
    maxFeeSol:     number,
    gasDropoffEth: number,
  ) {
    return this.program.methods.requestRelay({
      maxFee:     U64.to(maxFeeSol, LAMPORTS_PER_SOL),
      gasDropoff: U64.to(gasDropoffEth, GWEI_PER_ETH),
    }).accounts({
      payer,
      instance: this.instance,
      registeredChain: this.registeredChainPda(toChainId(chain)),
      outboxItem,
      relayRequest: this.relayRequestPda(outboxItem),
      systemProgram: SystemProgram.programId,
    }).instruction();
  }

  // ---- admin/assistant (=authority) relevant functions ----

  async getInstance() {
    const data = await this.program.account.instance.fetch(this.instance);
    return {
      owner:        data.owner,
      assistant:    data.assistant,
      feeRecipient: data.feeRecipient,
      solPriceUsd:  U64.from(data.solPrice, USD_UNIT),
    };
  }

  async getRegisteredChain(chain: Chain) {
    const data = await this.program.account.registeredChain.fetch(
      this.registeredChainPda(toChainId(chain))
    );
    
    return {
      paused:           data.basePrice.eq(U64.MAX),
      maxGasDropoffEth: U64.from(data.maxGasDropoff, GWEI_PER_ETH),
      basePriceUsd:     U64.from(data.basePrice,     USD_UNIT    ),
      nativePriceUsd:   U64.from(data.nativePrice,   USD_UNIT    ),
      gasPriceGwei:     U64.from(data.gasPrice,      WEI_PER_GWEI),
    };
  }

  //returns null if no relay was requested, otherwise it the requested gas dropoff (in eth),
  //  which can be 0, so a strict === null check is required!
  async wasRelayRequested(outboxItem: PublicKey) {
    const relayRequest = await this.program.account.relayRequest.fetchNullable(
      this.relayRequestPda(outboxItem)
    );

    return relayRequest ? U64.from(relayRequest.requestedGasDropoff, GWEI_PER_ETH) : null;
  }

  async createInitalizeInstruction(feeRecipient: PublicKey) {
    if(!this.program.account.instance.fetchNullable(this.instance))
      throw new Error("Already initialized");

    const programData = programDataAddress(this.program.programId);

    const accInfo = await this.program.provider.connection.getAccountInfo(programData);
    if (!accInfo)
      throw new Error("Could not find program data account");

    const deserProgramData = deserializeLayout(programDataLayout, accInfo.data);
    if (!deserProgramData.upgradeAuthority.isSome)
      throw new Error("Could not determine program owner from program data.");

    return this.program.methods.initialize().accounts({
      owner: deserProgramData.upgradeAuthority.value,
      instance: this.instance,
      feeRecipient,
      programData,
      systemProgram: SystemProgram.programId,
    }).instruction();
  }

  async createSetAssistantInstruction(assistant: PublicKey) {
    const {owner, assistant: currentAssistant} = await this.getInstance();
    if (currentAssistant.equals(assistant))
      throw new Error("Is already assistant");

    return this.program.methods.setAssistant().accounts({
      owner,
      instance: this.instance,
      assistant,
    }).instruction();
  }

  async createSetFeeRecipientInstruction(feeRecipient: PublicKey) {
    if (feeRecipient.equals(PublicKey.default))
      throw new Error("Fee recipient cannot be default public key");

    const {owner, feeRecipient: currentFeeRecipient} = await this.getInstance();
    if (currentFeeRecipient.equals(feeRecipient))
      throw new Error("Is already feeRecipient");

    return this.program.methods.setFeeRecipient().accounts({
      owner,
      instance: this.instance,
      feeRecipient,
    }).instruction();
  }

  async createRegisterChainInstruction(authority: PublicKey, chain: Chain) {
    const chainId = toChainId(chain);
    return this.program.methods.registerChain({chainId}).accounts({
      authority,
      instance: this.instance,
      registeredChain: this.registeredChainPda(chainId),
      systemProgram: SystemProgram.programId,
    }).instruction();
  }

  async createUpdateSolPriceInstruction(authority: PublicKey, solPriceUsd: number) {
    return this.program.methods.updateSolPrice({
      solPrice: U64.to(solPriceUsd, USD_UNIT),
    }).accounts({
      authority,
      instance: this.instance,
    }).instruction();
  }

  async createUpdateChainParamsInstruction(
    authority:        PublicKey,
    chain:            Chain,
    maxGasDropoffEth: number,
    basePriceUsd:     number,
  ) {
    return this.program.methods.updateChainParams({
      maxGasDropoff: U64.to(maxGasDropoffEth, GWEI_PER_ETH),
      basePrice:     U64.to(basePriceUsd,     USD_UNIT    ),
    }).accounts({
      authority,
      instance: this.instance,
      registeredChain: this.registeredChainPda(toChainId(chain)),
    }).instruction();
  }

  async createPauseRelayForChainInstruction(authority: PublicKey, chain: Chain) {
    return this.program.methods.updateChainParams({
      maxGasDropoff: U64.to(0, 1),
      basePrice:     U64.MAX,
    }).accounts({
      authority,
      instance: this.instance,
      registeredChain: this.registeredChainPda(toChainId(chain)),
    }).instruction();
  }

  async createUpdateChainPricesInstruction(
    authority: PublicKey,
    chain: Chain,
    nativePriceUsd: number,
    gasPriceGwei: number,
  ) {
    return this.program.methods.updateChainPrices({
      nativePrice: U64.to(nativePriceUsd, USD_UNIT),
      gasPrice:    U64.to(gasPriceGwei, WEI_PER_GWEI),
    }).accounts({
      authority,
      instance: this.instance,
      registeredChain: this.registeredChainPda(toChainId(chain)),
    }).instruction();
  }

  async createCloseRelayInstruction(authority: PublicKey, outboxItem: PublicKey) {
    return this.program.methods.closeRelay().accounts({
      authority,
      instance: this.instance,
      relayRequest: this.relayRequestPda(outboxItem),
    }).instruction();
  }

  // ---- private ----

  private registeredChainPda(chainId: number) {
    return derivePda(
      [SEED_PREFIX_REGISTERED_CHAIN, chainIdToBeBytes(chainId)],
      this.program.programId
    );
  }

  private relayRequestPda(outboxItem: PublicKey) {
    return derivePda(
      [SEED_PREFIX_RELAY_REQUEST, outboxItem.toBytes()],
      this.program.programId
    );
  }
}

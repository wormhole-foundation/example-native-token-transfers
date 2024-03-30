import { web3 } from "@coral-xyz/anchor";
import * as spl from "@solana/spl-token";
import { Connection, PublicKey } from "@solana/web3.js";
import {
  ChainAddress,
  ChainContext,
  Signer,
  Wormhole,
  WormholeMessageId,
  amount,
  chainToPlatform,
  deserialize,
  encoding,
  serialize,
  signSendWait as ssw,
  toChainId,
} from "@wormhole-foundation/sdk-connect";
import {
  EvmChains,
  EvmPlatform,
  getEvmSignerForSigner,
} from "@wormhole-foundation/sdk-evm";
import {
  SolanaChains,
  SolanaPlatform,
  getSolanaSignAndSendSigner,
} from "@wormhole-foundation/sdk-solana";
import { ethers } from "ethers";

import "@wormhole-foundation/sdk-evm-core";
import "@wormhole-foundation/sdk-solana-core";

import { DummyTokenMintAndBurn__factory } from "../evm/ethers-ci-contracts/factories/DummyToken.sol/DummyTokenMintAndBurn__factory.js";
import { DummyToken__factory } from "../evm/ethers-ci-contracts/factories/DummyToken.sol/DummyToken__factory.js";
import { ERC1967Proxy__factory } from "../evm/ethers-ci-contracts/factories/ERC1967Proxy__factory.js";
import { NttManager__factory } from "../evm/ethers-ci-contracts/factories/NttManager__factory.js";
import { TransceiverStructs__factory } from "../evm/ethers-ci-contracts/factories/TransceiverStructs__factory.js";
import { TrimmedAmountLib__factory } from "../evm/ethers-ci-contracts/factories/TrimmedAmount.sol/TrimmedAmountLib__factory.js";
import { WormholeTransceiver__factory } from "../evm/ethers-ci-contracts/factories/WormholeTransceiver__factory.js";

import solanaTiltKey from "./solana-tilt.json"; // from https://github.com/wormhole-foundation/wormhole/blob/main/solana/keys/solana-devnet.json

import { Ntt } from "../definitions/src/index.js";
import { EvmNtt } from "../evm/src/ntt.js";
import { SolanaNtt } from "../solana/src/ntt.js";

// Note: Currently, in order for this to run, the evm bindings with extra contracts must be build
// To do that, at the root, run `npm run generate:test`

export const NETWORK: "Devnet" = "Devnet";

const ETH_PRIVATE_KEY =
  "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"; // Ganache default private key
const SOL_PRIVATE_KEY = web3.Keypair.fromSecretKey(
  new Uint8Array(solanaTiltKey)
);

export type Mode = "locking" | "burning";
interface Signers {
  address: ChainAddress;
  signer: Signer;
  nativeSigner: any;
}

interface StartingCtx {
  context: ChainContext<typeof NETWORK>;
  mode: Mode;
}

export interface Ctx extends StartingCtx {
  signers: Signers;
  contracts?: {
    token: string;
    manager: string;
    transceiver: string;
  };
}

export const wh = new Wormhole(NETWORK, [EvmPlatform, SolanaPlatform], {
  ...(process.env["CI"]
    ? {
        chains: {
          // TODO: remove with next version of sdk
          Bsc: { rpc: "http://eth-devnet2:8545" },
        },
      }
    : {
        api: "http://localhost:7071",
        chains: {
          Ethereum: { rpc: "http://localhost:8545" },
          Bsc: { rpc: "http://localhost:8546" },
          Solana: { rpc: "http://localhost:8899" },
        },
      }),
});

export async function deploy(_ctx: StartingCtx): Promise<Ctx> {
  const platform = chainToPlatform(_ctx.context!.chain);
  const ctx = { ..._ctx, signers: await getSigners(_ctx) };
  switch (platform) {
    case "Evm":
      return deployEvm(ctx);
    case "Solana":
      return deploySolana(ctx);
    default:
      throw new Error(
        "Unsupported platform " + platform + " (add it to deploy)"
      );
  }
}

export async function link(chainInfos: Ctx[]) {
  console.log("\nStarting linking process");
  console.log("========================");
  for (const targetInfo of chainInfos) {
    const toRegister = chainInfos.filter(
      (peerInfo) => peerInfo.context.chain !== targetInfo.context.chain
    );

    console.log(
      "Registering peers for ",
      targetInfo.context.chain,
      ": ",
      toRegister.map((x) => x.context.chain)
    );

    await Promise.all(
      toRegister.map(async (peerInfo) => {
        await setupPeer(targetInfo, peerInfo);
      })
    );
  }
  console.log("Finished linking!");
}

export async function transferWithChecks(
  sourceCtx: Ctx,
  destinationCtx: Ctx,
  useRelayer: boolean = false
) {
  const sendAmt = "0.01";

  const srcAmt = amount.units(
    amount.parse(sendAmt, sourceCtx.context.config.nativeTokenDecimals)
  );
  const dstAmt = amount.units(
    amount.parse(sendAmt, destinationCtx.context.config.nativeTokenDecimals)
  );

  const [managerBalanceBeforeSend, userBalanceBeforeSend] =
    await getManagerAndUserBalance(sourceCtx);
  const [managerBalanceBeforeRecv, userBalanceBeforeRecv] =
    await getManagerAndUserBalance(destinationCtx);

  const { signer: srcSigner } = sourceCtx.signers;
  const { signer: dstSigner } = destinationCtx.signers;

  const sender = Wormhole.chainAddress(srcSigner.chain(), srcSigner.address());
  const receiver = Wormhole.chainAddress(
    dstSigner.chain(),
    dstSigner.address()
  );

  console.log("Calling transfer on: ", sourceCtx.context.chain);
  const srcNtt = await getNtt(sourceCtx);
  const transferTxs = srcNtt.transfer(sender.address, srcAmt, receiver, false);
  const txids = await signSendWait(sourceCtx.context, transferTxs, srcSigner);

  const srcCore = await sourceCtx.context.getWormholeCore();
  const msgId = (
    await srcCore.parseTransaction(txids[txids.length - 1]!.txid)
  )[0]!;

  if (!useRelayer) await receive(msgId, destinationCtx);

  const [managerBalanceAfterSend, userBalanceAfterSend] =
    await getManagerAndUserBalance(sourceCtx);
  const [managerBalanceAfterRecv, userBalanceAfterRecv] =
    await getManagerAndUserBalance(destinationCtx);

  checkBalances(
    sourceCtx.mode,
    [managerBalanceBeforeSend, managerBalanceAfterSend],
    [userBalanceBeforeSend, userBalanceAfterSend],
    srcAmt
  );

  checkBalances(
    destinationCtx.mode,
    [managerBalanceBeforeRecv, managerBalanceAfterRecv],
    [userBalanceBeforeRecv, userBalanceAfterRecv],
    -dstAmt
  );
}

// Wrap signSendWait from sdk to provide full error message
async function signSendWait(
  ctx: ChainContext<typeof NETWORK>,
  txs: any,
  signer: Signer
) {
  try {
    return await ssw(ctx, txs, signer);
  } catch (e) {
    console.error(e);
    throw e;
  }
}

async function getNtt(
  ctx: Ctx
): Promise<Ntt<typeof NETWORK, typeof ctx.context.chain>> {
  const platform = chainToPlatform(ctx.context.chain);
  switch (platform) {
    case "Evm":
      const rpc = await ctx.context.getRpc();
      const entt = new EvmNtt(NETWORK, ctx.context.chain as EvmChains, rpc, {
        token: ctx.contracts!.token,
        manager: ctx.contracts!.manager,
        transceiver: {
          wormhole: ctx.contracts!.transceiver,
        },
      });
      //@ts-ignore
      entt.chainId = (await (rpc as ethers.Provider).getNetwork()).chainId;
      return entt;
    case "Solana":
      return new SolanaNtt(
        NETWORK,
        ctx.context.chain as SolanaChains,
        await ctx.context.getRpc(),
        ctx.context.config.contracts.coreBridge!,
        {
          token: ctx.contracts!.token,
          manager: ctx.contracts!.manager,
          transceiver: {
            wormhole: ctx.contracts!.transceiver,
          },
        }
      );
    default:
      throw new Error(
        "Unsupported platform " + platform + " (add it to getNtt)"
      );
  }
}

async function getNativeSigner(ctx: Partial<Ctx>): Promise<any> {
  const platform = chainToPlatform(ctx.context!.chain);
  switch (platform) {
    case "Evm":
      const wallet = new ethers.Wallet(ETH_PRIVATE_KEY);
      const nonceManager = new ethers.NonceManager(wallet);
      return nonceManager.connect(await ctx.context!.getRpc());
    case "Solana":
      return SOL_PRIVATE_KEY;
    default:
      throw "Unsupported platform " + platform + " (add it to getNativeSigner)";
  }
}

async function getSigners(ctx: Partial<Ctx>): Promise<Signers> {
  const platform = chainToPlatform(ctx.context!.chain);
  switch (platform) {
    case "Evm":
      const evmNativeSigner = await getNativeSigner(ctx);
      const evmSigner = await getEvmSignerForSigner(
        ctx.context!.chain as EvmChains,
        evmNativeSigner
      );
      return {
        nativeSigner: evmNativeSigner,
        signer: evmSigner,
        address: Wormhole.chainAddress(evmSigner.chain(), evmSigner.address()),
      };
    case "Solana":
      const solNativeSigner = await getNativeSigner(ctx);
      const solSigner = await getSolanaSignAndSendSigner(
        await ctx.context!.getRpc(),
        solNativeSigner
      );
      return {
        nativeSigner: solNativeSigner,
        signer: solSigner,
        address: Wormhole.chainAddress(solSigner.chain(), solSigner.address()),
      };
    default:
      throw new Error(
        "Unsupported platform " + platform + " (add it to getSigner)"
      );
  }
}

async function deployEvm(ctx: Ctx): Promise<Ctx> {
  const { signer, nativeSigner: wallet } = ctx.signers;

  // Deploy libraries used by various things
  console.log("Deploying transceiverStructs");
  const transceiverStructsFactory = new TransceiverStructs__factory(wallet);
  const transceiverStructsContract = await transceiverStructsFactory.deploy();
  await transceiverStructsContract.waitForDeployment();

  console.log("Deploying trimmed amount");
  const trimmedAmountFactory = new TrimmedAmountLib__factory(wallet);
  const trimmedAmountContract = await trimmedAmountFactory.deploy();
  await trimmedAmountContract.waitForDeployment();

  console.log("Deploying dummy token");
  // Deploy the NTT token
  const NTTAddress = await new (ctx.mode === "locking"
    ? DummyToken__factory
    : DummyTokenMintAndBurn__factory)(wallet).deploy();
  await NTTAddress.waitForDeployment();

  if (ctx.mode === "locking") {
    await tryAndWaitThrice(() =>
      NTTAddress.mintDummy(
        signer.address(),
        amount.units(amount.parse("100", 18))
      )
    );
  }

  const transceiverStructsAddress =
    await transceiverStructsContract.getAddress();
  const trimmedAmountAddress = await trimmedAmountContract.getAddress();
  const ERC20NTTAddress = await NTTAddress.getAddress();

  const myObj = {
    "src/libraries/TransceiverStructs.sol:TransceiverStructs":
      transceiverStructsAddress,
    "src/libraries/TrimmedAmount.sol:TrimmedAmountLib": trimmedAmountAddress,
  };

  const chainId = toChainId(ctx.context.chain);

  // https://github.com/search?q=repo%3Awormhole-foundation%2Fwormhole-connect%20__factory&type=code
  // https://github.com/wormhole-foundation/wormhole/blob/00f504ef452ae2d94fa0024c026be2d8cf903ad5/clients/js/src/evm.ts#L335

  console.log("Deploying manager implementation");
  const wormholeManager = new NttManager__factory(myObj, wallet);
  const managerAddress = await wormholeManager.deploy(
    ERC20NTTAddress, // Token address
    ctx.mode === "locking" ? 0 : 1, // Lock
    chainId, // chain id
    0, // Locking time
    true
  );
  await managerAddress.waitForDeployment();

  console.log("Deploying manager proxy");
  const ERC1967ProxyFactory = new ERC1967Proxy__factory(wallet);
  const managerProxyAddress = await ERC1967ProxyFactory.deploy(
    await managerAddress.getAddress(),
    "0x"
  );
  await managerProxyAddress.waitForDeployment();

  // After we've deployed the proxy AND the manager then connect to the proxy with the interface of the manager.
  const manager = NttManager__factory.connect(
    await managerProxyAddress.getAddress(),
    wallet
  );

  console.log("Deploy transceiver implementation");
  const WormholeTransceiverFactory = new WormholeTransceiver__factory(
    myObj,
    wallet
  );
  const WormholeTransceiverAddress = await WormholeTransceiverFactory.deploy(
    // List of useful wormhole contracts - https://github.com/wormhole-foundation/wormhole/blob/00f504ef452ae2d94fa0024c026be2d8cf903ad5/ethereum/ts-scripts/relayer/config/ci/contracts.json
    await manager.getAddress(),
    ctx.context.config.contracts.coreBridge!, // Core wormhole contract - https://docs.wormhole.com/wormhole/blockchain-environments/evm#local-network-contract -- may need to be changed to support other chains
    ctx.context.config.contracts.relayer!, // Relayer contract -- double check these...https://github.com/wormhole-foundation/wormhole/blob/main/sdk/js/src/relayer/__tests__/wormhole_relayer.ts
    "0x0000000000000000000000000000000000000000", // TODO - Specialized relayer??????
    200, // Consistency level
    500000n // Gas limit
  );
  await WormholeTransceiverAddress.waitForDeployment();

  // // Setup with the proxy
  console.log("Deploy transceiver proxy");
  const transceiverProxyFactory = new ERC1967Proxy__factory(wallet);
  const transceiverProxyAddress = await transceiverProxyFactory.deploy(
    await WormholeTransceiverAddress.getAddress(),
    "0x"
  );
  await transceiverProxyAddress.waitForDeployment();

  const transceiver = WormholeTransceiver__factory.connect(
    await transceiverProxyAddress.getAddress(),
    wallet
  );

  // initialize() on both the manager and transceiver
  console.log("Initialize the manager");
  await tryAndWaitThrice(() => manager.initialize());
  console.log("Initialize the transceiver");
  await tryAndWaitThrice(() => transceiver.initialize());

  // Setup the initial calls, like transceivers for the manager
  console.log("Set transceiver for manager");
  await tryAndWaitThrice(() =>
    transceiver.getAddress().then((addr) => manager.setTransceiver(addr))
  );

  console.log("Set outbound limit for manager");
  await tryAndWaitThrice(() =>
    manager.setOutboundLimit(amount.units(amount.parse("10000", 18)))
  );

  return {
    ...ctx,
    contracts: {
      transceiver: await transceiverProxyAddress.getAddress(),
      manager: await managerProxyAddress.getAddress(),
      token: ERC20NTTAddress,
    },
  };
}

async function deploySolana(ctx: Ctx): Promise<Ctx> {
  const { signer, nativeSigner: keypair } = ctx.signers;
  const connection = (await ctx.context.getRpc()) as Connection;
  const address = new PublicKey(signer.address());
  const coreAddress = ctx.context.config.contracts.coreBridge!;
  console.log(`Using public key: ${address}`);

  const mint = await spl.createMint(connection, keypair, address, null, 9);
  console.log("Created mint", mint.toString());

  const tokenAccount = await spl.createAssociatedTokenAccount(
    connection,
    keypair,
    mint,
    address
  );
  console.log("Created token account", tokenAccount.toString());

  if (ctx.mode === "locking") {
    const amt = amount.units(amount.parse("100", 9));
    await spl.mintTo(connection, keypair, mint, tokenAccount, keypair, amt);
    console.log(`Minted ${amt} tokens`);
  }

  const managerProgramId =
    ctx.mode === "locking"
      ? "NTTManager222222222222222222222222222222222"
      : "NTTManager111111111111111111111111111111111";

  const manager = new SolanaNtt(NETWORK, "Solana", connection, coreAddress, {
    token: mint.toBase58(),
    manager: managerProgramId,
    transceiver: {
      wormhole: managerProgramId,
    },
  });

  // Check to see if already deployed, dirty env
  const mgrProgram = await connection.getAccountInfo(
    new PublicKey(manager.pdas.configAccount())
  );
  if (!mgrProgram || mgrProgram.data.length === 0) {
    await spl.setAuthority(
      connection,
      keypair,
      mint,
      keypair,
      0,
      manager.pdas.tokenAuthority()
    );
    console.log(
      "Set token authority to",
      manager.pdas.tokenAuthority().toString()
    );

    const initTxs = manager.initialize({
      payer: keypair,
      owner: keypair,
      chain: "Solana",
      mint,
      outboundLimit: 1000000000n,
      mode: ctx.mode,
    });
    await signSendWait(ctx.context, initTxs, signer);
    console.log("Initialized ntt at", manager.program.programId.toString());

    const registrTxs = manager.registerTransceiver({
      payer: keypair,
      owner: keypair,
      transceiver: manager.program.programId,
    });
    await signSendWait(ctx.context, registrTxs, signer);
    console.log("Registered transceiver with self");
  }

  return {
    ...ctx,
    contracts: {
      transceiver: manager.pdas.emitterAccount().toString(),
      manager: manager.program.programId.toString(),
      token: mint.toString(),
    },
  };
}

async function setupPeer(targetCtx: Ctx, peerCtx: Ctx) {
  const target = targetCtx.context;
  const peer = peerCtx.context;

  const targetPlatform = chainToPlatform(target.chain);
  const peerPlatform = chainToPlatform(peer.chain);

  const peerContracts = peerCtx.contracts!;

  const managerAddress = Wormhole.parseAddress(
    peer.chain,
    peerContracts.manager
  )
    .toUniversalAddress()
    .toString();
  const transceiverEmitter = Wormhole.parseAddress(
    peer.chain,
    peerContracts.transceiver
  )
    .toUniversalAddress()
    .toString();

  const tokenDecimals = chainToPlatform(target.chain) === "Evm" ? 18 : 9;
  const inboundLimit = amount.units(amount.parse("100", tokenDecimals));

  if (targetPlatform === "Evm") {
    // TODO: add these methods to Interface
    // so we dont need switch
    const targetContracts = targetCtx.contracts!;
    const { nativeSigner: wallet } = targetCtx.signers;

    const manager = NttManager__factory.connect(
      targetContracts.manager,
      wallet
    );
    const transceiver = WormholeTransceiver__factory.connect(
      targetContracts.transceiver,
      wallet
    );

    const peerChainId = toChainId(peer.chain);

    console.log("Evm inbound", inboundLimit);
    await tryAndWaitThrice(() =>
      manager.setPeer(peerChainId, managerAddress, tokenDecimals, inboundLimit)
    );
    await tryAndWaitThrice(() =>
      transceiver.setWormholePeer(peerChainId, transceiverEmitter)
    );

    if (peerPlatform === "Evm") {
      await tryAndWaitThrice(() =>
        transceiver.setIsWormholeEvmChain(peerChainId, true)
      );
      await tryAndWaitThrice(() =>
        transceiver.setIsWormholeRelayingEnabled(peerChainId, true)
      );
    }
  } else if (targetPlatform === "Solana") {
    const { signer, nativeSigner: keypair } = targetCtx.signers;
    const manager = (await getNtt(targetCtx)) as SolanaNtt<"Devnet", "Solana">;
    const setXcvrPeerTxs = manager.setWormholeTransceiverPeer({
      payer: keypair,
      owner: keypair,
      chain: peer.chain,
      address: encoding.hex.decode(transceiverEmitter),
    });
    await signSendWait(target, setXcvrPeerTxs, signer);

    console.log("Solana inbound", inboundLimit);

    const setPeerTxs = manager.setPeer({
      payer: keypair,
      owner: keypair,
      chain: peer.chain,
      address: encoding.hex.decode(managerAddress),
      limit: inboundLimit,
      tokenDecimals,
    });
    await signSendWait(target, setPeerTxs, signer);
  }
}

async function receive(msgId: WormholeMessageId, destination: Ctx) {
  const { signer, address: sender } = destination.signers;
  console.log(
    `Fetching VAA ${toChainId(msgId.chain)}/${encoding.hex.encode(
      msgId.emitter.toUint8Array(),
      false
    )}/${msgId.sequence}`
  );

  // TODO: can this be done in single step now?
  const _vaa = await wh.getVaa(msgId, "Uint8Array");
  const vaa = deserialize("Ntt:WormholeTransfer", serialize(_vaa!));

  console.log("Calling redeem on: ", destination.context.chain);
  const ntt = await getNtt(destination);
  const redeemTxs = ntt.redeem([vaa!], sender.address);
  await signSendWait(destination.context, redeemTxs, signer);
}

async function getManagerAndUserBalance(ctx: Ctx): Promise<[bigint, bigint]> {
  const chain = ctx.context;
  const contracts = ctx.contracts!;
  const { address } = ctx.signers;
  const tokenAddress = Wormhole.parseAddress(chain.chain, contracts.token);
  const accountAddress = address.address.toString();

  // TODO: add getCustodyAddress to interface
  let managerAddress = Wormhole.parseAddress(
    chain.chain,
    contracts.manager
  ).toString();
  if (chain.chain === "Solana") {
    const ntt = (await getNtt(ctx)) as SolanaNtt<"Devnet", "Solana">;
    const conf = await ntt.getConfig();
    managerAddress = conf.custody.toBase58();
  }

  const mbal = await chain.getBalance(managerAddress, tokenAddress);
  const abal = await chain.getBalance(accountAddress, tokenAddress);
  return [mbal ?? 0n, abal ?? 0n];
}

function checkBalances(
  mode: Mode,
  managerBalances: [bigint, bigint],
  userBalances: [bigint, bigint],
  check: bigint
) {
  console.log(mode, managerBalances, userBalances, check);

  const [managerBefore, managerAfter] = managerBalances;
  if (
    mode === "burning"
      ? !(managerAfter === 0n)
      : !(managerAfter === managerBefore + check)
  ) {
    throw new Error(
      `Source manager amount incorrect: before ${managerBefore.toString()}, after ${managerAfter.toString()}`
    );
  }

  const [userBefore, userAfter] = userBalances;
  if (!(userAfter == userBefore - check)) {
    throw new Error(
      `Source user amount incorrect: before ${userBefore.toString()}, after ${userAfter.toString()}`
    );
  }
}

async function tryAndWaitThrice(
  txGen: () => Promise<ethers.ContractTransactionResponse>
): Promise<ethers.ContractTransactionReceipt | null> {
  // these tests have some issue with getting a nonce mismatch despite everything being awaited
  let attempts = 0;
  while (attempts < 3) {
    try {
      return await (await txGen()).wait();
    } catch (e) {
      attempts++;
      if (attempts < 3) {
        console.log(`retry ${attempts}...`);
      } else {
        throw e;
      }
    }
  }
  return null;
}

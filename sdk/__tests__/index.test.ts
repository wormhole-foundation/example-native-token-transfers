import { web3 } from "@coral-xyz/anchor";
import * as spl from "@solana/spl-token";
import { Connection, PublicKey } from "@solana/web3.js";
import {
  Chain,
  ChainContext,
  Signer,
  Wormhole,
  WormholeCore,
  WormholeMessageId,
  amount,
  chainToPlatform,
  deserialize,
  deserializeLayout,
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
  SolanaSendSigner,
} from "@wormhole-foundation/sdk-solana";
import { ethers } from "ethers";
import * as fs from "fs";

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

import { EvmWormholeCore } from "@wormhole-foundation/sdk-evm-core";
import { SolanaWormholeCore } from "@wormhole-foundation/sdk-solana-core";
import { Ntt } from "../definitions/src/index.js";
import { EvmNtt } from "../evm/src/ntt.js";
import { SolanaNtt } from "../solana/src/ntt.js";

const NETWORK: "Devnet" = "Devnet";
const ETH_PRIVATE_KEY =
  "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"; // Ganache default private key
const SOL_PRIVATE_KEY = web3.Keypair.fromSecretKey(
  new Uint8Array(solanaTiltKey)
);

type Mode = "locking" | "burning";
type Ctx = {
  context: ChainContext<typeof NETWORK>;
  mode: Mode;
  contracts?: {
    token: string;
    manager: string;
    transceiver: string;
  };
};

const cases = [
  ["Solana", ["Ethereum", "Bsc"]],
  // ["Ethereum", ["Bsc", "Solana"]],
  // ["Bsc", ["Ethereum", "Solana"]],
];

const wh = new Wormhole(NETWORK, [EvmPlatform, SolanaPlatform], {
  api: "http://127.0.0.1:7071",
  chains: {
    Ethereum: {
      //rpc: "http://eth-devnet:8545",
      rpc: "http://localhost:8545",
      contracts: {
        coreBridge: "0xC89Ce4735882C9F0f0FE26686c53074E09B0D550",
        relayer: "0x53855d4b64E9A3CF59A84bc768adA716B5536BC5",
      },
    },
    Bsc: {
      //rpc: "http://eth-devnet2:8545",
      rpc: "http://localhost:8546",
      contracts: {
        coreBridge: "0xC89Ce4735882C9F0f0FE26686c53074E09B0D550",
        relayer: "0x53855d4b64E9A3CF59A84bc768adA716B5536BC5",
      },
    },
    Solana: {
      //rpc: "http://solana-devnet:8899",
      rpc: "http://localhost:8899",
      contracts: { coreBridge: "Bridge1p5gheXUvJ6jGWGeCsgPKgnE3YgdGKRVCMY9o" },
    },
  },
});

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

async function getCore(ctx: Ctx): Promise<WormholeCore<typeof NETWORK, any>> {
  const platform = chainToPlatform(ctx.context.chain);
  switch (platform) {
    case "Evm":
      return new EvmWormholeCore(
        NETWORK,
        ctx.context.chain as EvmChains,
        await ctx.context.getRpc(),
        ctx.context.config.contracts
      );
    case "Solana":
      return new SolanaWormholeCore(
        NETWORK,
        ctx.context.chain as SolanaChains,
        await ctx.context.getRpc(),
        ctx.context.config.contracts
      );
    default:
      throw new Error(
        "Unsupported platform " + platform + " (add it to getNtt)"
      );
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

async function getNativeSigner(ctx: Ctx): Promise<any> {
  const platform = chainToPlatform(ctx.context.chain);
  switch (platform) {
    case "Evm":
      const wallet = new ethers.Wallet(ETH_PRIVATE_KEY);
      return wallet.connect(await ctx.context.getRpc());
    case "Solana":
      return SOL_PRIVATE_KEY;
    default:
      throw "Unsupported platform " + platform + " (add it to getNativeSigner)";
  }
}

async function getSigner(ctx: Ctx): Promise<Signer> {
  const platform = chainToPlatform(ctx.context.chain);
  switch (platform) {
    case "Evm":
      return getEvmSignerForSigner(
        ctx.context.chain as EvmChains,
        await getNativeSigner(ctx)
      );
    case "Solana":
      return new SolanaSendSigner(
        await ctx.context.getRpc(),
        "Solana",
        await getNativeSigner(ctx)
        // true // Debug
      );
    default:
      throw new Error(
        "Unsupported platform " + platform + " (add it to getSigner)"
      );
  }
}

async function deploy(ctx: Ctx): Promise<Ctx> {
  const platform = chainToPlatform(ctx.context.chain);
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

async function deployEvm(ctx: Ctx): Promise<Ctx> {
  const signer = await getSigner(ctx);
  const wallet = (await getNativeSigner(ctx)) as ethers.Wallet;

  const overrides = {
    gasLimit: 1000000n,
  };

  // Deploy libraries used by various things
  console.log("Deploying transceiverStructs");
  const transceiverStructsFactory = new TransceiverStructs__factory(wallet);
  const transceiverStructsContract = await transceiverStructsFactory.deploy();
  await transceiverStructsContract.waitForDeployment();

  console.log("Deploying trimmed amount");
  const trimmedAmountFactory = new TrimmedAmountLib__factory(wallet);
  const trimmedAmountContract = await trimmedAmountFactory.deploy(overrides);
  await trimmedAmountContract.waitForDeployment();

  console.log("Deploying dummy token");
  // Deploy the NTT token
  const NTTAddress = await new (ctx.mode === "locking"
    ? DummyToken__factory
    : DummyTokenMintAndBurn__factory)(wallet).deploy(overrides);
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
    true,
    {
      gasLimit: 30000000n,
    }
  );
  await managerAddress.waitForDeployment();

  await sleep(2);
  console.log("Deploying manager proxy");
  const ERC1967ProxyFactory = new ERC1967Proxy__factory(wallet);
  const managerProxyAddress = await ERC1967ProxyFactory.deploy(
    await managerAddress.getAddress(),
    "0x",
    overrides
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
    500000n, // Gas limit
    {
      gasLimit: 30000000n,
    }
  );
  await WormholeTransceiverAddress.waitForDeployment();

  // // Setup with the proxy
  await sleep(2);
  console.log("Deploy transceiver proxy");
  const transceiverProxyFactory = new ERC1967Proxy__factory(wallet);
  const transceiverProxyAddress = await transceiverProxyFactory.deploy(
    await WormholeTransceiverAddress.getAddress(),
    "0x",
    overrides
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
  await tryAndWaitThrice(async () =>
    manager.setTransceiver(await transceiver.getAddress())
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
  const signer = await getSigner(ctx);
  const connection = (await ctx.context.getRpc()) as Connection;
  const address = new PublicKey(signer.address());
  const coreAddress = ctx.context.config.contracts.coreBridge!;
  console.log(`Using public key: ${address}`);

  const mint = await spl.createMint(
    connection,
    SOL_PRIVATE_KEY,
    address,
    null,
    9
  );
  console.log("Created mint", mint.toString());

  const tokenAccount = await spl.createAssociatedTokenAccount(
    connection,
    SOL_PRIVATE_KEY,
    mint,
    address
  );
  console.log("Created token account", tokenAccount.toString());

  if (ctx.mode === "locking") {
    const amt = amount.units(amount.parse("100", 9));
    await spl.mintTo(
      connection,
      SOL_PRIVATE_KEY,
      mint,
      tokenAccount,
      SOL_PRIVATE_KEY,
      amt
    );
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
      SOL_PRIVATE_KEY,
      mint,
      SOL_PRIVATE_KEY,
      0, // mint
      manager.pdas.tokenAuthority()
    );
    console.log(
      "Set token authority to",
      manager.pdas.tokenAuthority().toString()
    );

    const initTxs = manager.initialize({
      payer: SOL_PRIVATE_KEY,
      owner: SOL_PRIVATE_KEY,
      chain: "Solana",
      mint,
      outboundLimit: 1000000000n,
      mode: ctx.mode,
    });
    await signSendWait(ctx.context, initTxs, signer);
    console.log("Initialized ntt at", manager.program.programId.toString());

    const registrTxs = manager.registerTransceiver({
      payer: SOL_PRIVATE_KEY,
      owner: SOL_PRIVATE_KEY,
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

  const tokenDecimals = peer.config.nativeTokenDecimals;

  if (targetPlatform === "Evm") {
    const inboundLimit = amount.units(amount.parse("10000", tokenDecimals));
    const targetContracts = targetCtx.contracts!;
    const signer = (await getNativeSigner(targetCtx)) as ethers.Wallet;

    const manager = NttManager__factory.connect(
      targetContracts.manager,
      signer
    );
    const transceiver = WormholeTransceiver__factory.connect(
      targetContracts.transceiver,
      signer
    );

    await tryAndWaitThrice(() =>
      manager.setPeer(
        toChainId(peerCtx.context.chain),
        managerAddress,
        tokenDecimals,
        inboundLimit
      )
    );
    await tryAndWaitThrice(() =>
      transceiver.setWormholePeer(toChainId(peer.chain), transceiverEmitter)
    );

    if (peerPlatform === "Evm") {
      await tryAndWaitThrice(() =>
        transceiver.setIsWormholeEvmChain(toChainId(peer.chain), true)
      );
      await tryAndWaitThrice(() =>
        transceiver.setIsWormholeRelayingEnabled(toChainId(peer.chain), true)
      );
    }
  } else if (targetPlatform === "Solana") {
    const signer = await getSigner(targetCtx);
    const manager = (await getNtt(targetCtx)) as SolanaNtt<"Devnet", "Solana">;
    const setXcvrPeerTxs = manager.setWormholeTransceiverPeer({
      payer: SOL_PRIVATE_KEY,
      owner: SOL_PRIVATE_KEY,
      chain: peer.chain,
      address: encoding.hex.decode(transceiverEmitter),
    });
    await signSendWait(target, setXcvrPeerTxs, signer);

    const setPeerTxs = manager.setPeer({
      payer: SOL_PRIVATE_KEY,
      owner: SOL_PRIVATE_KEY,
      chain: peer.chain,
      address: encoding.hex.decode(managerAddress),
      limit: 1000000000n,
      tokenDecimals,
    });
    await signSendWait(target, setPeerTxs, signer);
  }
}

async function link(chainInfos: Ctx[]) {
  console.log("\nStarting linking process");
  console.log("========================");
  for (const targetInfo of chainInfos) {
    for (const peerInfo of chainInfos) {
      if (peerInfo.context.chain === targetInfo.context.chain) continue;
      console.log(
        `Registering ${peerInfo.context.chain} on ${targetInfo.context.chain}`
      );
      await setupPeer(targetInfo, peerInfo);
    }
  }
  console.log("Finished linking!");
}

async function receive(msgId: WormholeMessageId, destination: Ctx) {
  console.log(
    `Fetching VAA ${toChainId(msgId.chain)}/${encoding.hex.encode(
      msgId.emitter.toUint8Array(),
      false
    )}/${msgId.sequence}`
  );

  const _vaa = await wh.getVaa(msgId, "Uint8Array");
  const vaa = deserialize("Ntt:WormholeTransfer", serialize(_vaa!));
  console.log(vaa);

  const signer = await getSigner(destination);
  console.log(signer);
  const sender = Wormhole.chainAddress(signer.chain(), signer.address());
  console.log(sender);
  const ntt = await getNtt(destination);

  console.log("Calling redeem on: ", destination.context.chain);
  const redeemTxs = ntt.redeem([vaa!], sender.address);
  await signSendWait(destination.context, redeemTxs, signer);
}

async function getManagerAndUserBalance(ctx: Ctx): Promise<[bigint, bigint]> {
  const chain = ctx.context;
  const contracts = ctx.contracts!;
  const tokenAddress = Wormhole.parseAddress(chain.chain, contracts.token);
  const address = (await getSigner(ctx)).address();
  return [
    (await chain.getBalance(contracts.manager, tokenAddress))!,
    (await chain.getBalance(address, tokenAddress))!,
  ];
}

async function transferWithChecks(
  sourceCtx: Ctx,
  destinationCtx: Ctx,
  useRelayer: boolean = false
) {
  const amt = amount.units(
    amount.parse("0.001", sourceCtx.context.config.nativeTokenDecimals)
  );
  const scaledAmt = amount.units(amount.parse("1", 9));

  const [managerBalanceBeforeSend, userBalanceBeforeSend] =
    await getManagerAndUserBalance(sourceCtx);
  const [managerBalanceBeforeRecv, userBalanceBeforeRecv] =
    await getManagerAndUserBalance(destinationCtx);

  const srcSigner = await getSigner(sourceCtx);
  const dstSigner = await getSigner(destinationCtx);

  const sender = Wormhole.chainAddress(srcSigner.chain(), srcSigner.address());
  console.log(dstSigner.chain(), dstSigner.address());
  const receiver = Wormhole.chainAddress(
    dstSigner.chain(),
    dstSigner.address()
  );

  const srcNtt = await getNtt(sourceCtx);
  const srcCore = await getCore(sourceCtx);

  console.log("Calling transfer on: ", sourceCtx.context.chain);
  const transferTxs = srcNtt.transfer(sender.address, amt, receiver, false);
  const txids = await signSendWait(sourceCtx.context, transferTxs, srcSigner);
  const msgId = (
    await srcCore.parseTransaction(txids[txids.length - 1]!.txid)
  )[0]!;

  if (!useRelayer) await receive(msgId, destinationCtx);

  const [managerBalanceAfterSend, userBalanceAfterSend] =
    await getManagerAndUserBalance(sourceCtx);
  const [managerBalanceAfterRecv, userBalanceAfterRecv] =
    await getManagerAndUserBalance(destinationCtx);

  const srcPlatform = chainToPlatform(sourceCtx.context.chain);
  const dstPlatform = chainToPlatform(destinationCtx.context.chain);

  const sourceCheckAmount = srcPlatform === "Solana" ? scaledAmt : amt;
  const destinationCheckAmount = dstPlatform === "Solana" ? scaledAmt : amt;

  checkBalances(
    sourceCtx.mode,
    [managerBalanceBeforeSend, managerBalanceAfterSend],
    [userBalanceBeforeSend, userBalanceAfterSend],
    sourceCheckAmount
  );
  checkBalances(
    destinationCtx.mode,
    [managerBalanceBeforeRecv, managerBalanceAfterRecv],
    [userBalanceBeforeRecv, userBalanceAfterRecv],
    destinationCheckAmount
  );
}

function checkBalances(
  mode: Mode,
  managerBalance: [bigint, bigint],
  userBalances: [bigint, bigint],
  check: bigint
) {
  const [managerBefore, managerAfter] = managerBalance;
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

async function sleep(seconds: number) {
  // sleep for 2 seconds
  await Promise.resolve(
    new Promise((resolve) => setTimeout(resolve, seconds * 1000))
  );
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
      sleep(1);
      if (attempts < 3) {
        console.log(`retry ${attempts}...`);
      } else {
        throw e;
      }
    }
  }
  return null;
}

describe("Hub Tests", function () {
  test.each(cases)("Test %s Hub", async (source, destinations) => {
    // Get chain context objects
    let hubChain = wh.getChain(source as Chain);
    let [spokeChainA, spokeChainB] = [
      wh.getChain(destinations[0] as Chain),
      wh.getChain(destinations[1] as Chain),
    ];

    const redeploy = false;

    let hub: Ctx, spokeA: Ctx, spokeB: Ctx;
    if (redeploy) {
      // Deploy contracts for hub chain
      console.log("Deploying contracts");
      [hub, spokeA, spokeB] = await Promise.all([
        deploy({ context: hubChain, mode: "locking" }),
        deploy({ context: spokeChainA, mode: "burning" }),
        deploy({ context: spokeChainB, mode: "burning" }),
      ]);
      console.log(
        "Deployed: ",
        { chain: hub.context.chain, ...hub.contracts },
        { chain: spokeA.context.chain, ...spokeA.contracts },
        { chain: spokeB.context.chain, ...spokeB.contracts }
      );

      // Link contracts
      console.log("Linking Peers");
      await link([hub, spokeA, spokeB]);

      fs.writeFileSync(
        "contracts.json",
        JSON.stringify({
          hub: { chain: hub.context.chain, ...hub.contracts },
          spokeA: { chain: spokeA.context.chain, ...spokeA.contracts },
          spokeB: { chain: spokeB.context.chain, ...spokeB.contracts },
        })
      );
    } else {
      const cached = JSON.parse(fs.readFileSync("contracts.json", "utf8"));
      hub = { context: hubChain, mode: "locking", contracts: cached["hub"] };
      spokeA = {
        context: spokeChainA,
        mode: "burning",
        contracts: cached["spokeA"],
      };
      spokeB = {
        context: spokeChainB,
        contracts: cached["spokeB"],
        mode: "burning",
      };
    }

    console.log(hub, spokeA, spokeB);

    // Transfer tokens from hub to spoke and check balances
    console.log("Transfer hub to spoke A");
    await transferWithChecks(hub, spokeA);

    // Transfer between spokes and check balances
    console.log("Transfer spoke A to spoke B");
    await transferWithChecks(spokeA, spokeB);

    // Transfer back to hub and check balances
    console.log("Transfer spoke B to hub");
    await transferWithChecks(spokeB, hub);
  });
});

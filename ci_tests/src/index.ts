import {
  CONTRACTS,
  ChainId,
  ChainName,
  coalesceChainId,
  coalesceChainName,
  getEmitterAddressEth,
  getSignedVAAWithRetry,
  parseSequenceFromLogEth,
  postVaaSolana,
} from "@certusone/wormhole-sdk";
import { WormholeRelayer__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts";
import {
  getDeliveryHashFromLog,
  getWormholeLog,
} from "@certusone/wormhole-sdk/lib/cjs/relayer";
import { NodeWallet } from "@certusone/wormhole-sdk/lib/cjs/solana";
import { PostedMessageData } from "@certusone/wormhole-sdk/lib/cjs/solana/wormhole";
import { BN, web3 } from "@coral-xyz/anchor";
import { NodeHttpTransport } from "@improbable-eng/grpc-web-node-http-transport";
import * as spl from "@solana/spl-token";
import {
  BigNumber,
  ContractReceipt,
  ContractTransaction,
  Wallet,
  providers,
  utils,
} from "ethers";
import { DummyTokenMintAndBurn__factory } from "../evm_binding/factories/DummyToken.sol/DummyTokenMintAndBurn__factory";
import { DummyToken__factory } from "../evm_binding/factories/DummyToken.sol/DummyToken__factory";
import { ERC1967Proxy__factory } from "../evm_binding/factories/ERC1967Proxy__factory";
import { NttManager__factory } from "../evm_binding/factories/NttManager__factory";
import { TransceiverStructs__factory } from "../evm_binding/factories/TransceiverStructs__factory";
import { TrimmedAmountLib__factory } from "../evm_binding/factories/TrimmedAmount.sol/TrimmedAmountLib__factory";
import { WormholeTransceiver__factory } from "../evm_binding/factories/WormholeTransceiver__factory";
import { NTT, NttProgramId } from "../solana_binding/ts/sdk";
import solanaTiltKey from "./solana-tilt.json"; // from https://github.com/wormhole-foundation/wormhole/blob/main/solana/keys/solana-devnet.json
import { submitAccountantVAA } from "./accountant";

// NOTE: This test uses ethers-v5 as it has proven to be significantly faster than v6.
// Additionally, the @certusone/wormhole-sdk currently has a v5 dependency.
// This does have the following shortcomings:
// - v5 does not parse the errors from ganache correctly (v6 does)
// - there are intermittent nonce errors, even following a `.wait()` (see `tryAndWaitThrice`)

type Mode = "locking" | "burning";
type ChainDetails = EVMChainDetails | SolanaChainDetails;
interface EVMChainDetails extends BaseDetails {
  type: "evm";
  signer: Wallet;
}
interface SolanaChainDetails extends BaseDetails {
  type: "solana";
  signer: web3.Keypair;
  manager: NTT;
}
interface BaseDetails {
  chainId: ChainId;
  chainName: ChainName;
  mode: Mode;
  transceiverAddress: string;
  managerAddress: string;
  NTTTokenAddress: string;
  wormholeCoreAddress: string;
}

const ETH_PRIVATE_KEY =
  "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"; // Ganache default private key
const ETH_PUBLIC_KEY = "0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1";
const ETH_SIGNER = new Wallet(
  ETH_PRIVATE_KEY,
  new providers.JsonRpcProvider("http://eth-devnet:8545")
);
const BSC_SIGNER = new Wallet(
  ETH_PRIVATE_KEY,
  new providers.JsonRpcProvider("http://eth-devnet2:8545")
);
const SOL_PRIVATE_KEY = web3.Keypair.fromSecretKey(
  new Uint8Array(solanaTiltKey)
);
const SOL_PUBLIC_KEY = SOL_PRIVATE_KEY.publicKey;
const SOL_CONNECTION = new web3.Connection(
  "http://solana-devnet:8899",
  "confirmed"
);
const SOL_CORE_ADDRESS = "Bridge1p5gheXUvJ6jGWGeCsgPKgnE3YgdGKRVCMY9o";
const RELAYER_CONTRACT = "0x53855d4b64E9A3CF59A84bc768adA716B5536BC5";

// Wormhole format means that addresses are bytes32 instead of addresses when using them to support other chains.
function addressToBytes32(address: string): string {
  return `0x000000000000000000000000${address.substring(2)}`;
}

const getEmitter = (chainInfo: ChainDetails) =>
  chainInfo.type === "evm"
    ? getEmitterAddressEth(chainInfo.transceiverAddress)
    : chainInfo.manager.emitterAccountAddress().toBuffer().toString("hex");

async function waitForRelay(
  tx: ContractReceipt,
  chainId: ChainId,
  sourceProvider: providers.Provider,
  destinationProvider: providers.Provider,
  retryTime: number = 100
) {
  const log = getWormholeLog(
    tx,
    CONTRACTS.DEVNET.ethereum.core,
    getEmitterAddressEth(RELAYER_CONTRACT),
    0
  );
  const deliveryHash = await getDeliveryHashFromLog(
    log.log,
    chainId,
    sourceProvider,
    tx.blockHash
  );
  const wormholeRelayer = WormholeRelayer__factory.connect(
    RELAYER_CONTRACT,
    destinationProvider
  );
  let success = false;
  while (!success) {
    await new Promise((resolve) => setTimeout(resolve, retryTime));
    const successBlock = await wormholeRelayer.deliverySuccessBlock(
      deliveryHash
    );
    if (successBlock.gt("0")) {
      success = true;
    }
  }
}

async function tryAndWaitThrice(
  txGen: () => Promise<ContractTransaction>
): Promise<ContractReceipt> {
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
}

async function deployEvm(
  signer: Wallet,
  chainName: ChainName,
  mode: Mode
): Promise<EVMChainDetails> {
  // Deploy libraries used by various things
  console.log("Deploying libraries of transceiverStructs and trimmedAmounts");
  const transceiverStructsFactory = new TransceiverStructs__factory(signer);
  const transceiverStructsContract = await transceiverStructsFactory.deploy();

  const trimmedAmountFactory = new TrimmedAmountLib__factory(signer);
  const trimmedAmountContract = await trimmedAmountFactory.deploy();

  // Deploy the NTT token
  const NTTAddress = await new (mode === "locking"
    ? DummyToken__factory
    : DummyTokenMintAndBurn__factory)(signer).deploy();

  if (mode === "locking") {
    await tryAndWaitThrice(() =>
      NTTAddress.mintDummy(ETH_PUBLIC_KEY, utils.parseEther("100"))
    );
  }

  const transceiverStructsAddress = await transceiverStructsContract.address;
  const trimmedAmountAddress = await trimmedAmountContract.address;
  const ERC20NTTAddress = await NTTAddress.address;

  const myObj = {
    "src/libraries/TransceiverStructs.sol:TransceiverStructs":
      transceiverStructsAddress,
    "src/libraries/TrimmedAmount.sol:TrimmedAmountLib": trimmedAmountAddress,
  };

  const chainId = coalesceChainId(chainName);

  // https://github.com/search?q=repo%3Awormhole-foundation%2Fwormhole-connect%20__factory&type=code
  // https://github.com/wormhole-foundation/wormhole/blob/00f504ef452ae2d94fa0024c026be2d8cf903ad5/clients/js/src/evm.ts#L335
  console.log("Deploying manager implementation");
  const wormholeManager = new NttManager__factory(myObj, signer);
  const managerAddress = await wormholeManager.deploy(
    ERC20NTTAddress, // Token address
    mode === "locking" ? 0 : 1, // Lock
    chainId, // chain id
    0, // Locking time
    true
  );

  console.log("Deploying manager proxy");
  const ERC1967ProxyFactory = new ERC1967Proxy__factory(signer);
  const managerProxyAddress = await ERC1967ProxyFactory.deploy(
    await managerAddress.address,
    "0x"
  );

  // // After we've deployed the proxy AND the manager then connect to the proxy with the interface of the manager.
  const manager = NttManager__factory.connect(
    await managerProxyAddress.address,
    signer
  );

  console.log("Deploy transceiver implementation");
  const WormholeTransceiverFactory = new WormholeTransceiver__factory(
    myObj,
    signer
  );
  const WormholeTransceiverAddress = await WormholeTransceiverFactory.deploy(
    // List of useful wormhole contracts - https://github.com/wormhole-foundation/wormhole/blob/00f504ef452ae2d94fa0024c026be2d8cf903ad5/ethereum/ts-scripts/relayer/config/ci/contracts.json
    await manager.address,
    "0xC89Ce4735882C9F0f0FE26686c53074E09B0D550", // Core wormhole contract - https://docs.wormhole.com/wormhole/blockchain-environments/evm#local-network-contract -- may need to be changed to support other chains
    RELAYER_CONTRACT, //"0xE66C1Bc1b369EF4F376b84373E3Aa004E8F4C083", // Relayer contract -- double check these...https://github.com/wormhole-foundation/wormhole/blob/main/sdk/js/src/relayer/__tests__/wormhole_relayer.ts
    "0x0000000000000000000000000000000000000000", // TODO - Specialized relayer??????
    200, // Consistency level
    500000 // Gas limit
  );

  // // Setup with the proxy
  console.log("Deploy transceiver proxy");
  const transceiverProxyFactory = new ERC1967Proxy__factory(signer);
  const transceiverProxyAddress = await transceiverProxyFactory.deploy(
    await WormholeTransceiverAddress.address,
    "0x"
  );
  const transceiver = WormholeTransceiver__factory.connect(
    await transceiverProxyAddress.address,
    signer
  );

  // initialize() on both the manager and transceiver
  console.log("Initialize the manager");
  await tryAndWaitThrice(() => manager.initialize());
  console.log("Initialize the transceiver");
  await tryAndWaitThrice(() => transceiver.initialize());

  // Setup the initial calls, like transceivers for the manager
  console.log("Set transceiver for manager");
  await tryAndWaitThrice(() => manager.setTransceiver(transceiver.address));

  console.log("Set outbound limit for manager");
  await tryAndWaitThrice(() =>
    manager.setOutboundLimit(utils.parseEther("10000"))
  );

  return {
    type: "evm",
    chainId,
    chainName,
    mode,
    transceiverAddress: transceiverProxyAddress.address,
    managerAddress: managerProxyAddress.address,
    NTTTokenAddress: ERC20NTTAddress,
    wormholeCoreAddress: "0xC89Ce4735882C9F0f0FE26686c53074E09B0D550", // Same on both of the chains
    signer,
  };
}

async function initSolana(
  mode: Mode,
  nttId: NttProgramId
): Promise<SolanaChainDetails> {
  console.log(
    "Using public key",
    SOL_PUBLIC_KEY.toString(),
    "and manager address",
    nttId
  );
  const manager = new NTT(SOL_CONNECTION, {
    nttId,
    wormholeId: SOL_CORE_ADDRESS,
  });
  const mint = await spl.createMint(
    SOL_CONNECTION,
    SOL_PRIVATE_KEY,
    SOL_PUBLIC_KEY,
    null,
    9
  );
  console.log("Created mint", mint.toString());
  const tokenAccount = await spl.createAssociatedTokenAccount(
    SOL_CONNECTION,
    SOL_PRIVATE_KEY,
    mint,
    SOL_PUBLIC_KEY
  );
  console.log("Created token account", tokenAccount.toString());
  if (mode === "locking") {
    await spl.mintTo(
      SOL_CONNECTION,
      SOL_PRIVATE_KEY,
      mint,
      tokenAccount,
      SOL_PRIVATE_KEY,
      utils.parseUnits("100", 9).toBigInt()
    );
    console.log("Minted 10000000 tokens");
  }
  await spl.setAuthority(
    SOL_CONNECTION,
    SOL_PRIVATE_KEY,
    mint,
    SOL_PRIVATE_KEY,
    0, // mint
    manager.tokenAuthorityAddress()
  );
  console.log(
    "Set token authority to",
    manager.tokenAuthorityAddress().toString()
  );

  await manager.initialize({
    payer: SOL_PRIVATE_KEY,
    owner: SOL_PRIVATE_KEY,
    chain: "solana",
    mint,
    outboundLimit: new BN(1000000000),
    mode,
  });
  console.log("Initialized ntt at", manager.program.programId.toString());

  // NOTE: this is a hack. The next instruction will fail if we don't wait
  // here, because the address lookup table is not yet available, despite
  // the transaction having been confirmed.
  // Looks like a bug, but I haven't investigated further. In practice, this
  // won't be an issue, becase the address lookup table will have been
  // created well before anyone is trying to use it, but we might want to be
  // mindful in the deploy script too.
  await new Promise((resolve) => setTimeout(resolve, 400));

  await manager.registerTransceiver({
    payer: SOL_PRIVATE_KEY,
    owner: SOL_PRIVATE_KEY,
    transceiver: manager.program.programId,
  });
  console.log("Registered transceiver with self");

  return {
    type: "solana",
    chainId: 1,
    chainName: "solana",
    mode,
    transceiverAddress: manager.emitterAccountAddress().toString(),
    managerAddress: manager.program.programId.toString(),
    NTTTokenAddress: mint.toString(),
    wormholeCoreAddress: SOL_CORE_ADDRESS,
    signer: SOL_PRIVATE_KEY,
    manager,
  };
}

async function setupPeer(targetInfo: ChainDetails, peerInfo: ChainDetails) {
  const managerAddress =
    peerInfo.type === "evm"
      ? addressToBytes32(peerInfo.managerAddress)
      : `0x${peerInfo.manager.program.programId.toBuffer().toString("hex")}`;
  const transceiverEmitter = `0x${getEmitter(peerInfo)}`;
  const tokenDecimals = peerInfo.type === "evm" ? 18 : 9;
  const inboundLimit =
    targetInfo.type === "evm"
      ? utils.parseEther("10000").toString()
      : "1000000000";
  if (targetInfo.type === "evm") {
    const manager = NttManager__factory.connect(
      targetInfo.managerAddress,
      targetInfo.signer
    );
    const transceiver = WormholeTransceiver__factory.connect(
      targetInfo.transceiverAddress,
      targetInfo.signer
    );
    await tryAndWaitThrice(() =>
      manager.setPeer(
        peerInfo.chainId,
        managerAddress,
        tokenDecimals,
        inboundLimit
      )
    );
    await tryAndWaitThrice(() =>
      transceiver.setWormholePeer(peerInfo.chainId, transceiverEmitter)
    );
    if (peerInfo.type === "evm") {
      await tryAndWaitThrice(() =>
        transceiver.setIsWormholeEvmChain(peerInfo.chainId, true)
      );
      await tryAndWaitThrice(() =>
        transceiver.setIsWormholeRelayingEnabled(peerInfo.chainId, true)
      );
    }
  } else if (targetInfo.type === "solana") {
    await targetInfo.manager.setWormholeTransceiverPeer({
      payer: SOL_PRIVATE_KEY,
      owner: SOL_PRIVATE_KEY,
      chain: coalesceChainName(peerInfo.chainId),
      address: Buffer.from(transceiverEmitter.substring(2), "hex"),
    });
    await targetInfo.manager.setPeer({
      payer: SOL_PRIVATE_KEY,
      owner: SOL_PRIVATE_KEY,
      chain: coalesceChainName(peerInfo.chainId),
      address: Buffer.from(managerAddress.substring(2), "hex"),
      limit: new BN(inboundLimit),
      tokenDecimals,
    });
  }
}

async function link(chainInfos: ChainDetails[]) {
  console.log("\nStarting linking process");
  console.log("========================");
  for (const targetInfo of chainInfos) {
    for (const peerInfo of chainInfos) {
      if (targetInfo === peerInfo) continue;
      console.log(
        `Registering ${peerInfo.chainName} on ${targetInfo.chainName}`
      );
      await setupPeer(targetInfo, peerInfo);
    }
  }
  console.log("Finished linking!");
}

async function getVAA(
  chainId: ChainId,
  emitterAddress: string,
  sequence: string
) {
  console.log(`Fetching VAA ${chainId}/${emitterAddress}/${sequence}`);
  return (
    await getSignedVAAWithRetry(
      ["http://guardian:7071"], // HTTP host for the Guardian
      chainId,
      emitterAddress,
      sequence,
      {
        transport: NodeHttpTransport(),
      }
    )
  ).vaaBytes;
}

async function receive(
  chainId: ChainId,
  emitterAddress: string,
  sequence: string,
  chainDest: ChainDetails
) {
  // poll until the guardian(s) witness and sign the vaa
  const signedVAA = await getVAA(chainId, emitterAddress, sequence);

  if (chainDest.type === "evm") {
    const transceiver = WormholeTransceiver__factory.connect(
      chainDest.transceiverAddress,
      chainDest.signer
    );
    await tryAndWaitThrice(() => transceiver.receiveMessage(signedVAA));
  } else if (chainDest.type === "solana") {
    const vaa = Buffer.from(signedVAA);
    await postVaaSolana(
      SOL_CONNECTION,
      new NodeWallet(SOL_PRIVATE_KEY).signTransaction,
      SOL_CORE_ADDRESS,
      SOL_PUBLIC_KEY,
      vaa
    );
    const released = await chainDest.manager.redeem({
      payer: SOL_PRIVATE_KEY,
      vaa,
    });

    console.log(`called redeem on solana, released: ${released}`);
  }
}

async function getManagerAndUserBalance(
  chain: ChainDetails
): Promise<[BigNumber, BigNumber]> {
  if (chain.type === "evm") {
    const token = DummyToken__factory.connect(
      chain.NTTTokenAddress,
      chain.signer
    );
    return [
      await token.balanceOf(chain.managerAddress),
      await token.balanceOf(ETH_PUBLIC_KEY),
    ];
  } else if (chain.type === "solana") {
    const mintAddress = await chain.manager.mintAccountAddress();
    const associatedTokenAddress = spl.getAssociatedTokenAddressSync(
      mintAddress,
      SOL_PUBLIC_KEY
    );
    const custodyAddress = await chain.manager.custodyAccountAddress(
      mintAddress
    );
    return [
      BigNumber.from(
        (await SOL_CONNECTION.getTokenAccountBalance(custodyAddress)).value
          .amount
      ),
      BigNumber.from(
        (await SOL_CONNECTION.getTokenAccountBalance(associatedTokenAddress))
          .value.amount
      ),
    ];
  }
}

async function transferWithChecks(
  sourceChain: ChainDetails,
  destinationChain: ChainDetails,
  useRelayer: boolean = false
) {
  const amount = utils.parseEther("1");
  const scaledAmount = utils.parseUnits("1", 9);
  let sequence: string;

  const [managerBalanceBeforeSend, userBalanceBeforeSend] =
    await getManagerAndUserBalance(sourceChain);
  const [managerBalanceBeforeRecv, userBalanceBeforeRecv] =
    await getManagerAndUserBalance(destinationChain);

  if (sourceChain.type === "evm") {
    const manager = NttManager__factory.connect(
      sourceChain.managerAddress,
      sourceChain.signer
    );
    const token = DummyToken__factory.connect(
      sourceChain.NTTTokenAddress,
      sourceChain.signer
    );
    await tryAndWaitThrice(() =>
      token.approve(sourceChain.managerAddress, amount)
    );
    const txResponse = await tryAndWaitThrice(() =>
      manager["transfer(uint256,uint16,bytes32,bytes32,bool,bytes)"](
        amount,
        destinationChain.chainId,
        destinationChain.type === "evm"
          ? addressToBytes32(ETH_PUBLIC_KEY)
          : `0x${SOL_PUBLIC_KEY.toBuffer().toString("hex")}`,
        destinationChain.type === "evm"
          ? addressToBytes32(ETH_PUBLIC_KEY)
          : `0x${SOL_PUBLIC_KEY.toBuffer().toString("hex")}`,
        false,
        useRelayer ? "0x01000100" : "0x01000101",
        useRelayer ? { value: utils.parseEther("1") } : {}
      )
    );
    if (useRelayer && destinationChain.type === "evm") {
      await waitForRelay(
        txResponse,
        sourceChain.chainId,
        sourceChain.signer.provider,
        destinationChain.signer.provider
      );
    }
    sequence = parseSequenceFromLogEth(
      txResponse,
      sourceChain.wormholeCoreAddress
    );
  } else if (sourceChain.type === "solana") {
    const mintAddress = await sourceChain.manager.mintAccountAddress();
    const associatedTokenAddress = spl.getAssociatedTokenAddressSync(
      mintAddress,
      SOL_PUBLIC_KEY
    );
    const outboxItem = await sourceChain.manager.transfer({
      payer: SOL_PRIVATE_KEY,
      from: associatedTokenAddress,
      fromAuthority: SOL_PRIVATE_KEY,
      amount: new BN(scaledAmount.toString()),
      recipientChain: destinationChain.chainName,
      recipientAddress: Buffer.from(
        addressToBytes32(ETH_PUBLIC_KEY).substring(2),
        "hex"
      ),
      shouldQueue: false,
    });
    const wormholeMessage =
      sourceChain.manager.wormholeMessageAccountAddress(outboxItem);
    const wormholeMessageAccount = await SOL_CONNECTION.getAccountInfo(
      wormholeMessage
    );
    if (wormholeMessageAccount === null) {
      throw new Error("wormhole message account not found");
    }
    const messageData = PostedMessageData.deserialize(
      wormholeMessageAccount.data
    );
    sequence = messageData.message.sequence.toString();
  }

  if (!useRelayer) {
    await receive(
      sourceChain.chainId,
      getEmitter(sourceChain),
      sequence,
      destinationChain
    );
  }

  const [managerBalanceAfterSend, userBalanceAfterSend] =
    await getManagerAndUserBalance(sourceChain);
  const [managerBalanceAfterRecv, userBalanceAfterRecv] =
    await getManagerAndUserBalance(destinationChain);
  const sourceCheckAmount =
    sourceChain.type === "solana" ? scaledAmount : amount;
  const destinationCheckAmount =
    destinationChain.type === "solana" ? scaledAmount : amount;

  if (
    sourceChain.mode === "burning"
      ? !managerBalanceAfterSend.eq(BigNumber.from("0"))
      : !managerBalanceAfterSend.eq(
          managerBalanceBeforeSend.add(sourceCheckAmount)
        )
  ) {
    throw new Error(
      `Source manager amount incorrect: before ${managerBalanceBeforeSend.toString()}, after ${managerBalanceAfterSend.toString()}`
    );
  }
  if (!userBalanceAfterSend.eq(userBalanceBeforeSend.sub(sourceCheckAmount))) {
    throw new Error(
      `Source user amount incorrect: before ${userBalanceBeforeSend.toString()}, after ${userBalanceAfterSend.toString()}`
    );
  }
  if (
    destinationChain.mode === "burning"
      ? !managerBalanceAfterRecv.eq(BigNumber.from("0"))
      : !managerBalanceAfterRecv.eq(
          managerBalanceBeforeRecv.sub(destinationCheckAmount)
        )
  ) {
    throw new Error(
      `Destination manager amount incorrect: before ${managerBalanceBeforeRecv.toString()}, after ${managerBalanceAfterRecv.toString()}`
    );
  }
  if (
    !userBalanceAfterRecv.eq(userBalanceBeforeRecv.add(destinationCheckAmount))
  ) {
    throw new Error(
      `Destination user amount incorrect: before ${userBalanceBeforeRecv.toString()}, after ${userBalanceAfterRecv.toString()}`
    );
  }
}

async function accountantRegistrations(chainInfos: ChainDetails[]) {
  console.log("Submitting NTT accountant registrations");
  // first submit hub init
  const hub = chainInfos[0];
  await submitAccountantVAA(await getVAA(hub.chainId, getEmitter(hub), "0"));
  // then submit spoke to hub registrations
  for (const chainInfo of chainInfos.slice(1)) {
    await submitAccountantVAA(
      await getVAA(chainInfo.chainId, getEmitter(chainInfo), "1")
    );
  }
  // then submit the rest of the registrations
  for (const chainInfo of chainInfos) {
    for (
      let idx = chainInfo === hub ? 0 : 1;
      idx < chainInfos.length - 1;
      idx++
    ) {
      await submitAccountantVAA(
        await getVAA(
          chainInfo.chainId,
          getEmitter(chainInfo),
          (1 + idx).toString()
        )
      );
    }
  }
}

async function testEthHub() {
  console.log("\n\n\n***\nEth Hub Test\n***");
  console.log("\nDeploying on eth-devnet");
  console.log("===============================================");
  const ethInfo = await deployEvm(ETH_SIGNER, "ethereum", "locking");
  console.log("\nDeploying on eth-devnet2");
  console.log("===============================================");
  const bscInfo = await deployEvm(BSC_SIGNER, "bsc", "burning");
  console.log("\nInitializing on solana-devnet");
  console.log("===============================================");
  const solInfo = await initSolana(
    "burning",
    "NTTManager111111111111111111111111111111111"
  );
  await link([ethInfo, bscInfo, solInfo]);
  await accountantRegistrations([ethInfo, bscInfo, solInfo]);
  console.log("\nStarting tests");
  console.log("========================");
  console.log("Eth <> BSC");
  await transferWithChecks(ethInfo, bscInfo);
  await transferWithChecks(bscInfo, ethInfo);
  console.log(`Eth <> Solana`);
  await transferWithChecks(ethInfo, solInfo);
  await transferWithChecks(solInfo, ethInfo);
  console.log(`BSC <> Solana`);
  await transferWithChecks(ethInfo, bscInfo);
  await transferWithChecks(bscInfo, solInfo);
  await transferWithChecks(solInfo, bscInfo);
  console.log("Eth <> BSC with relay");
  await transferWithChecks(ethInfo, bscInfo, true);
  await transferWithChecks(bscInfo, ethInfo, true);
  // TODO: corrupted or bad VAA usage
}

async function testSolanaHub() {
  console.log("\n\n\n***\nSolana Hub Test\n***");
  console.log("\nDeploying on eth-devnet");
  console.log("===============================================");
  const ethInfo = await deployEvm(ETH_SIGNER, "ethereum", "burning");
  console.log("\nDeploying on eth-devnet2");
  console.log("===============================================");
  const bscInfo = await deployEvm(BSC_SIGNER, "bsc", "burning");
  console.log("\nInitializing on solana-devnet");
  console.log("===============================================");
  const solInfo = await initSolana(
    "locking",
    "NTTManager222222222222222222222222222222222"
  );
  await link([solInfo, ethInfo, bscInfo]);
  await accountantRegistrations([solInfo, ethInfo, bscInfo]);
  console.log("\nStarting tests");
  console.log("========================");
  console.log("Solana -> Eth -> BSC -> Solana");
  await transferWithChecks(solInfo, ethInfo);
  await transferWithChecks(ethInfo, bscInfo);
  await transferWithChecks(bscInfo, solInfo);
}

async function test() {
  // register the relayers (taken from https://github.com/wormhole-foundation/wormhole/blob/main/wormchain/contracts/tools/__tests__/test_ntt_accountant.ts#L614)
  await submitAccountantVAA(
    Buffer.from(
      "010000000001006c9967aee739944b30ffcc01653f2030ea02c038adda26a8f5a790f191134dff1e1e48368af121a34806806140d4f56ec09e25067006e69c95b0c4c08b8897990000000000000000000001000000000000000000000000000000000000000000000000000000000000000400000000001ce9cf010000000000000000000000000000000000576f726d686f6c6552656c61796572010000000200000000000000000000000053855d4b64e9a3cf59a84bc768ada716b5536bc5",
      "hex"
    )
  );
  await submitAccountantVAA(
    Buffer.from(
      "01000000000100894be2c33626547e665cee73684854fbd8fc2eb79ec9ad724b1fb10d6cd24aaa590393870e6655697cd69d5553881ac8519e1282e7d3ae5fc26d7452d097651c00000000000000000000010000000000000000000000000000000000000000000000000000000000000004000000000445fb0b010000000000000000000000000000000000576f726d686f6c6552656c61796572010000000400000000000000000000000053855d4b64e9a3cf59a84bc768ada716b5536bc5",
      "hex"
    )
  );
  await testEthHub();
  await testSolanaHub();
}

test();

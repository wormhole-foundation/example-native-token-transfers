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
import {} from "@certusone/wormhole-sdk/lib/cjs/relayer/consts";
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
import { NTT } from "../solana_binding/ts/sdk";
import solanaTiltKey from "./solana-tilt.json"; // from https://github.com/wormhole-foundation/wormhole/blob/main/solana/keys/solana-devnet.json

// NOTE: This test uses ethers-v5 as it has proven to be significantly faster than v6.
// Additionally, the @certusone/wormhole-sdk currently has a v5 dependency.
// This does have the following shortcomings:
// - v5 does not parse the errors from ganache correctly (v6 does)
// - there are intermittent nonce errors, even following a `.wait()` (see `tryAndWaitThrice`)

// Chain details to keep track of during the testing
type ChainDetails = EVMChainDetails | SolanaChainDetails;
interface EVMChainDetails extends BaseDetails {
  type: "evm";
  signer: Wallet;
}
interface SolanaChainDetails extends BaseDetails {
  type: "solana";
  signer: web3.Keypair;
}
interface BaseDetails {
  chainId: ChainId;
  chainName: ChainName;
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
const SOL_NTT_CONTRACT = new NTT(SOL_CONNECTION, {
  nttId: "NTTManager111111111111111111111111111111111",
  wormholeId: SOL_CORE_ADDRESS,
});
const RELAYER_CONTRACT = "0x53855d4b64E9A3CF59A84bc768adA716B5536BC5";

// Wormhole format means that addresses are bytes32 instead of addresses when using them to support other chains.
function addressToBytes32(address: string): string {
  return `0x000000000000000000000000${address.substring(2)}`;
}

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
    addressToBytes32(RELAYER_CONTRACT).substring(2),
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
  lockingMode: boolean
): Promise<EVMChainDetails> {
  // Deploy libraries used by various things
  console.log("Deploying libraries of transceiverStructs and trimmedAmounts");
  const transceiverStructsFactory = new TransceiverStructs__factory(signer);
  const transceiverStructsContract = await transceiverStructsFactory.deploy();

  const trimmedAmountFactory = new TrimmedAmountLib__factory(signer);
  const trimmedAmountContract = await trimmedAmountFactory.deploy();

  // Deploy the NTT token
  const NTTAddress = await new (lockingMode
    ? DummyToken__factory
    : DummyTokenMintAndBurn__factory)(signer).deploy();

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
    lockingMode ? 0 : 1, // Lock
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
    transceiverAddress: transceiverProxyAddress.address,
    managerAddress: managerProxyAddress.address,
    NTTTokenAddress: ERC20NTTAddress,
    wormholeCoreAddress: "0xC89Ce4735882C9F0f0FE26686c53074E09B0D550", // Same on both of the chains
    signer,
  };
}

async function initSolana(lockingMode: boolean): Promise<SolanaChainDetails> {
  console.log("Using public key", SOL_PUBLIC_KEY.toString());
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
  if (lockingMode) {
    await spl.mintTo(
      SOL_CONNECTION,
      SOL_PRIVATE_KEY,
      mint,
      tokenAccount,
      SOL_PRIVATE_KEY,
      BigInt(10000000)
    );
    console.log("Minted 10000000 tokens");
  }
  await spl.setAuthority(
    SOL_CONNECTION,
    SOL_PRIVATE_KEY,
    mint,
    SOL_PRIVATE_KEY,
    0, // mint
    SOL_NTT_CONTRACT.tokenAuthorityAddress()
  );
  console.log(
    "Set token authority to",
    SOL_NTT_CONTRACT.tokenAuthorityAddress().toString()
  );

  await SOL_NTT_CONTRACT.initialize({
    payer: SOL_PRIVATE_KEY,
    owner: SOL_PRIVATE_KEY,
    chain: "solana",
    mint,
    outboundLimit: new BN(1000000000),
    mode: lockingMode ? "locking" : "burning",
  });
  console.log(
    "Initialized ntt at",
    SOL_NTT_CONTRACT.program.programId.toString()
  );

  await SOL_NTT_CONTRACT.registerTransceiver({
    payer: SOL_PRIVATE_KEY,
    owner: SOL_PRIVATE_KEY,
    transceiver: SOL_NTT_CONTRACT.program.programId,
  });
  console.log("Registered transceiver with self");

  return {
    type: "solana",
    chainId: 1,
    chainName: "solana",
    transceiverAddress: SOL_NTT_CONTRACT.emitterAccountAddress().toString(),
    managerAddress: SOL_NTT_CONTRACT.program.programId.toString(),
    NTTTokenAddress: mint.toString(),
    wormholeCoreAddress: SOL_CORE_ADDRESS,
    signer: SOL_PRIVATE_KEY,
  };
}

async function setupPeer(targetInfo: ChainDetails, peerInfo: ChainDetails) {
  const managerAddress =
    peerInfo.type === "evm"
      ? addressToBytes32(peerInfo.managerAddress)
      : `0x${SOL_NTT_CONTRACT.program.programId.toBuffer().toString("hex")}`;
  const transceiverEmitter =
    peerInfo.type === "evm"
      ? addressToBytes32(peerInfo.transceiverAddress)
      : `0x${SOL_NTT_CONTRACT.emitterAccountAddress()
          .toBuffer()
          .toString("hex")}`;
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
    await SOL_NTT_CONTRACT.setWormholeTransceiverPeer({
      payer: SOL_PRIVATE_KEY,
      owner: SOL_PRIVATE_KEY,
      chain: coalesceChainName(peerInfo.chainId),
      address: Buffer.from(transceiverEmitter.substring(2), "hex"),
    });
    await SOL_NTT_CONTRACT.setPeer({
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

async function receive(
  chainId: ChainId,
  emitterAddress: string,
  sequence: string,
  chainDest: ChainDetails
) {
  console.log(`Fetching VAA ${chainId}/${emitterAddress}/${sequence}`);
  // poll until the guardian(s) witness and sign the vaa
  const { vaaBytes: signedVAA } = await getSignedVAAWithRetry(
    ["http://guardian:7071"], // HTTP host for the Guardian
    chainId,
    emitterAddress,
    sequence,
    {
      transport: NodeHttpTransport(),
    }
  );

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
    const released = await SOL_NTT_CONTRACT.redeem({
      payer: SOL_PRIVATE_KEY,
      vaa,
    });

    console.log(`called redeem on solana, released: ${released}`);
  }
}

async function transferWithChecks(
  sourceChain: ChainDetails,
  destinationChain: ChainDetails,
  shouldPreMint: boolean,
  sourceBurn: boolean,
  useRelayer: boolean
) {
  const amount = utils.parseEther("1");
  const scaledAmount = utils.parseUnits("1", 9);
  let emitterAddress: string;
  let sequence: string;
  let balanceBeforeRecv: BigNumber;

  if (destinationChain.type === "evm") {
    const token = DummyToken__factory.connect(
      destinationChain.NTTTokenAddress,
      destinationChain.signer
    );
    balanceBeforeRecv = await token.balanceOf(ETH_PUBLIC_KEY);
  } else if (destinationChain.type === "solana") {
    const mintAddress = await SOL_NTT_CONTRACT.mintAccountAddress();
    const associatedTokenAddress = spl.getAssociatedTokenAddressSync(
      mintAddress,
      SOL_PUBLIC_KEY
    );
    balanceBeforeRecv = BigNumber.from(
      (await SOL_CONNECTION.getTokenAccountBalance(associatedTokenAddress))
        .value.amount
    );
  }

  if (sourceChain.type === "evm") {
    const manager = NttManager__factory.connect(
      sourceChain.managerAddress,
      sourceChain.signer
    );
    const token = DummyToken__factory.connect(
      sourceChain.NTTTokenAddress,
      sourceChain.signer
    );
    if (shouldPreMint) {
      await tryAndWaitThrice(() => token.mintDummy(ETH_PUBLIC_KEY, amount));
    }
    await tryAndWaitThrice(() =>
      token.approve(sourceChain.managerAddress, amount)
    );
    const balanceManagerBeforeSend1 = await token.balanceOf(
      sourceChain.managerAddress
    );
    const balanceUserBeforeSend1 = await token.balanceOf(ETH_PUBLIC_KEY);
    const txResponse = await tryAndWaitThrice(() =>
      manager["transfer(uint256,uint16,bytes32,bool,bytes)"](
        amount,
        destinationChain.chainId,
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
    emitterAddress = getEmitterAddressEth(sourceChain.transceiverAddress);
    sequence = parseSequenceFromLogEth(
      txResponse,
      sourceChain.wormholeCoreAddress
    );
    const balanceManagerAfterSend1 = await token.balanceOf(
      sourceChain.managerAddress
    );
    const balanceUserAfterSend1 = await token.balanceOf(ETH_PUBLIC_KEY);
    if (
      sourceBurn
        ? !balanceManagerAfterSend1.eq(BigNumber.from("0"))
        : !balanceManagerAfterSend1.eq(balanceManagerBeforeSend1.add(amount))
    ) {
      console.log("Manager amount incorrect");
    }

    if (!balanceUserAfterSend1.eq(balanceUserBeforeSend1.sub(amount))) {
      console.log("User amount incorrect");
    }
  } else if (sourceChain.type === "solana") {
    const mintAddress = await SOL_NTT_CONTRACT.mintAccountAddress();
    const associatedTokenAddress = spl.getAssociatedTokenAddressSync(
      mintAddress,
      SOL_PUBLIC_KEY
    );
    const custodyAddress = await SOL_NTT_CONTRACT.custodyAccountAddress(
      mintAddress
    );
    const balanceManagerBeforeSend2 = BigNumber.from(
      (await SOL_CONNECTION.getTokenAccountBalance(custodyAddress)).value.amount
    );
    const balanceUserBeforeSend2 = BigNumber.from(
      (await SOL_CONNECTION.getTokenAccountBalance(associatedTokenAddress))
        .value.amount
    );
    const outboxItem = await SOL_NTT_CONTRACT.transfer({
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
    const balanceManagerAfterSend2 = BigNumber.from(
      (await SOL_CONNECTION.getTokenAccountBalance(custodyAddress)).value.amount
    );
    const balanceUserAfterSend2 = BigNumber.from(
      (await SOL_CONNECTION.getTokenAccountBalance(associatedTokenAddress))
        .value.amount
    );
    if (!balanceManagerAfterSend2.eq(0) || !balanceManagerBeforeSend2.eq(0)) {
      console.log("Manager on burn chain has funds");
    }

    if (!balanceUserBeforeSend2.sub(scaledAmount).eq(balanceUserAfterSend2)) {
      console.log("User didn't transfer proper amount of funds on burn chain");
    }
    const wormholeMessage =
      SOL_NTT_CONTRACT.wormholeMessageAccountAddress(outboxItem);
    const wormholeMessageAccount = await SOL_CONNECTION.getAccountInfo(
      wormholeMessage
    );
    if (wormholeMessageAccount === null) {
      throw new Error("wormhole message account not found");
    }
    const messageData = PostedMessageData.deserialize(
      wormholeMessageAccount.data
    );
    emitterAddress = SOL_NTT_CONTRACT.emitterAccountAddress()
      .toBuffer()
      .toString("hex");
    sequence = messageData.message.sequence.toString();
  }

  if (!useRelayer) {
    await receive(
      sourceChain.chainId,
      emitterAddress,
      sequence,
      destinationChain
    );
  }

  if (destinationChain.type === "evm") {
    const token = DummyToken__factory.connect(
      destinationChain.NTTTokenAddress,
      destinationChain.signer
    );
    const balanceAfterRecv = await token.balanceOf(ETH_PUBLIC_KEY);
    if (!balanceAfterRecv.eq(balanceBeforeRecv.add(amount))) {
      console.log("User amount receive incorrect");
    }
  } else if (destinationChain.type === "solana") {
    const mintAddress = await SOL_NTT_CONTRACT.mintAccountAddress();
    const associatedTokenAddress = spl.getAssociatedTokenAddressSync(
      mintAddress,
      SOL_PUBLIC_KEY
    );
    const balanceAfterRecv = BigNumber.from(
      (await SOL_CONNECTION.getTokenAccountBalance(associatedTokenAddress))
        .value.amount
    );
    if (!balanceAfterRecv.eq(balanceBeforeRecv.add(scaledAmount))) {
      console.log(
        `User amount 1 receive incorrect: before ${balanceBeforeRecv.toString()}, after ${balanceAfterRecv.toString()}`
      );
    }
  }
}

async function testEthHub() {
  console.log("\nDeploying on eth-devnet");
  console.log("===============================================");
  const ethInfo = await deployEvm(ETH_SIGNER, "ethereum", true);
  console.log("\nDeploying on eth-devnet2");
  console.log("===============================================");
  const bscInfo = await deployEvm(BSC_SIGNER, "bsc", false);
  console.log("\nInitializing on solana-devnet");
  console.log("===============================================");
  const solInfo = await initSolana(false);
  await link([ethInfo, bscInfo, solInfo]);
  console.log("\nStarting tests");
  console.log("========================");
  console.log("Eth <> BSC");
  await transferWithChecks(ethInfo, bscInfo, true, false, false);
  await transferWithChecks(bscInfo, ethInfo, false, true, false);
  console.log(`Eth <> Solana`);
  await transferWithChecks(ethInfo, solInfo, true, false, false);
  await transferWithChecks(solInfo, ethInfo, false, true, false);
  console.log(`BSC <> Solana`);
  await transferWithChecks(bscInfo, solInfo, true, true, false);
  await transferWithChecks(solInfo, bscInfo, false, true, false);
  console.log("Eth <> BSC with relay");
  await transferWithChecks(ethInfo, bscInfo, true, false, true);
  await transferWithChecks(bscInfo, ethInfo, false, true, true);
  // TODO: corrupted or bad VAA usage
}

testEthHub();

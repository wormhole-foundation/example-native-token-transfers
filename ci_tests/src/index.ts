import {
  CONTRACTS,
  ChainId,
  ChainName,
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
import { NTT } from "../solana_binding/ts/sdk";

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
  chainId: number;
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
  new Uint8Array([
    14, 173, 153, 4, 176, 224, 201, 111, 32, 237, 183, 185, 159, 247, 22, 161,
    89, 84, 215, 209, 212, 137, 10, 92, 157, 49, 29, 192, 101, 164, 152, 70, 87,
    65, 8, 174, 214, 157, 175, 126, 98, 90, 54, 24, 100, 177, 247, 77, 19, 112,
    47, 44, 165, 109, 233, 102, 14, 86, 109, 29, 134, 145, 132, 141,
  ])
); // from https://github.com/wormhole-foundation/wormhole/blob/main/solana/keys/solana-devnet.json
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

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

async function deployEth(
  signer: Wallet,
  chain_id: number,
  chainName: ChainName
): Promise<EVMChainDetails> {
  // Deploy libraries used by various things
  console.log("Deploying libraries of transceiverStructs and trimmedAmounts");
  const transceiverStructsFactory = new TransceiverStructs__factory(signer);
  const transceiverStructsContract = await transceiverStructsFactory.deploy();

  const trimmedAmountFactory = new TrimmedAmountLib__factory(signer);
  const trimmedAmountContract = await trimmedAmountFactory.deploy();

  // Deploy the NTT token
  let NTTAddress;
  let tokenSetting;
  if (chain_id == 2) {
    // ETH?
    console.log("Deploy locking NTT token");
    const ERC20LockingFactory = new DummyToken__factory(signer);
    NTTAddress = await ERC20LockingFactory.deploy();
    tokenSetting = 0; // Lock
  } else {
    console.log("Deploy burning NTT token");
    const ERC20BurningFactory = new DummyTokenMintAndBurn__factory(signer);
    NTTAddress = await ERC20BurningFactory.deploy();
    tokenSetting = 1; // Burn
  }

  const transceiverStructsAddress = await transceiverStructsContract.address;
  const trimmedAmountAddress = await trimmedAmountContract.address;
  const ERC20NTTAddress = await NTTAddress.address;

  const myObj = {
    "src/libraries/TransceiverStructs.sol:TransceiverStructs":
      transceiverStructsAddress,
    "src/libraries/TrimmedAmount.sol:TrimmedAmountLib": trimmedAmountAddress,
  };

  // https://github.com/search?q=repo%3Awormhole-foundation%2Fwormhole-connect%20__factory&type=code
  // https://github.com/wormhole-foundation/wormhole/blob/00f504ef452ae2d94fa0024c026be2d8cf903ad5/clients/js/src/evm.ts#L335
  console.log("Deploying manager implementation");
  const wormholeManager = new NttManager__factory(myObj, signer);
  const managerAddress = await wormholeManager.deploy(
    ERC20NTTAddress, // Token address
    tokenSetting, // Lock
    chain_id, // chain id
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
    chainId: chain_id,
    chainName,
    transceiverAddress: transceiverProxyAddress.address,
    managerAddress: managerProxyAddress.address,
    NTTTokenAddress: ERC20NTTAddress,
    wormholeCoreAddress: "0xC89Ce4735882C9F0f0FE26686c53074E09B0D550", // Same on both of the chains
    signer,
  };
}

async function initSolana(): Promise<SolanaChainDetails> {
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
  // await spl.mintTo(
  //   SOL_CONNECTION,
  //   SOL_PRIVATE_KEY,
  //   mint,
  //   tokenAccount,
  //   SOL_PRIVATE_KEY,
  //   BigInt(10000000)
  // );
  // console.log("Minted 10000000 tokens");
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
    mode: "burning",
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

async function link(
  ethInfo: EVMChainDetails,
  bscInfo: EVMChainDetails,
  solInfo: SolanaChainDetails
) {
  // Hook up all the important things together
  /*
    - Manager peer
    - Wormhole peer
    - inbound limits
    https://github.com/wormhole-foundation/example-native-token-transfers/blob/main/evm/test/IntegrationStandalone.t.sol
    */
  console.log("\nStarting linking process");
  console.log("========================");

  const manager1 = NttManager__factory.connect(
    ethInfo.managerAddress,
    ETH_SIGNER
  );
  const manager2 = NttManager__factory.connect(
    bscInfo.managerAddress,
    BSC_SIGNER
  );

  const transceiver1 = WormholeTransceiver__factory.connect(
    ethInfo.transceiverAddress,
    ETH_SIGNER
  );
  const transceiver2 = WormholeTransceiver__factory.connect(
    bscInfo.transceiverAddress,
    BSC_SIGNER
  );

  // Would make sense to store the 'client' with a generalized interface instead of the
  console.log("Set manager peers");
  await tryAndWaitThrice(() =>
    manager1.setPeer(
      bscInfo.chainId,
      addressToBytes32(bscInfo.managerAddress),
      18 // decimals
    )
  );
  await tryAndWaitThrice(() =>
    manager1.setPeer(
      solInfo.chainId,
      `0x${SOL_NTT_CONTRACT.program.programId.toBuffer().toString("hex")}`,
      9 // decimals
    )
  );
  await tryAndWaitThrice(() =>
    manager2.setPeer(
      ethInfo.chainId,
      addressToBytes32(ethInfo.managerAddress),
      18 // decimals
    )
  );
  await tryAndWaitThrice(() =>
    manager2.setPeer(
      solInfo.chainId,
      `0x${SOL_NTT_CONTRACT.program.programId.toBuffer().toString("hex")}`,
      9 // decimals
    )
  );

  console.log("Set wormhole Peers");
  await tryAndWaitThrice(() =>
    transceiver1.setWormholePeer(
      bscInfo.chainId,
      addressToBytes32(bscInfo.transceiverAddress)
    )
  );
  await tryAndWaitThrice(() =>
    transceiver1.setWormholePeer(
      solInfo.chainId,
      `0x${SOL_NTT_CONTRACT.emitterAccountAddress().toBuffer().toString("hex")}`
    )
  );
  await tryAndWaitThrice(() =>
    transceiver2.setWormholePeer(
      ethInfo.chainId,
      addressToBytes32(ethInfo.transceiverAddress)
    )
  );
  await tryAndWaitThrice(() =>
    transceiver2.setWormholePeer(
      solInfo.chainId,
      `0x${SOL_NTT_CONTRACT.emitterAccountAddress().toBuffer().toString("hex")}`
    )
  );

  console.log("Set inbound limits");
  await tryAndWaitThrice(() =>
    manager1.setInboundLimit(utils.parseEther("10000"), bscInfo.chainId)
  );
  await tryAndWaitThrice(() =>
    manager2.setInboundLimit(utils.parseEther("10000"), ethInfo.chainId)
  );

  console.log("Setting transceiver to be an EVM transceiver");
  await tryAndWaitThrice(() =>
    transceiver1.setIsWormholeEvmChain(bscInfo.chainId)
  );
  await tryAndWaitThrice(() =>
    transceiver2.setIsWormholeEvmChain(ethInfo.chainId)
  );

  console.log("Enable relaying");
  await tryAndWaitThrice(() =>
    transceiver1.setIsWormholeRelayingEnabled(bscInfo.chainId, true)
  );
  await tryAndWaitThrice(() =>
    transceiver2.setIsWormholeRelayingEnabled(ethInfo.chainId, true)
  );

  console.log("Set Solana peers");
  await SOL_NTT_CONTRACT.setWormholeTransceiverPeer({
    payer: SOL_PRIVATE_KEY,
    owner: SOL_PRIVATE_KEY,
    chain: "ethereum",
    address: Buffer.from(
      addressToBytes32(ethInfo.transceiverAddress).substring(2),
      "hex"
    ),
  });
  await SOL_NTT_CONTRACT.setWormholeTransceiverPeer({
    payer: SOL_PRIVATE_KEY,
    owner: SOL_PRIVATE_KEY,
    chain: "bsc",
    address: Buffer.from(
      addressToBytes32(bscInfo.transceiverAddress).substring(2),
      "hex"
    ),
  });
  await SOL_NTT_CONTRACT.setPeer({
    payer: SOL_PRIVATE_KEY,
    owner: SOL_PRIVATE_KEY,
    chain: "ethereum",
    address: Buffer.from(
      addressToBytes32(ethInfo.managerAddress).substring(2),
      "hex"
    ),
    limit: new BN(1000000000),
    tokenDecimals: 18,
  });
  await SOL_NTT_CONTRACT.setPeer({
    payer: SOL_PRIVATE_KEY,
    owner: SOL_PRIVATE_KEY,
    chain: "bsc",
    address: Buffer.from(
      addressToBytes32(bscInfo.managerAddress).substring(2),
      "hex"
    ),
    limit: new BN(1000000000),
    tokenDecimals: 18,
  });

  console.log("Finished linking!");
}

async function test(
  ethInfo: EVMChainDetails,
  bscInfo: EVMChainDetails,
  solInfo: SolanaChainDetails
) {
  /*
    Tests to run 
    - Basic Move from A to B with balance checks
    - Corrupted or bad VAA usage
    - Relayer vs non-relayer path
    */
  console.log("\nStarting tests");
  console.log("========================");

  await BackAndForthBaseTest(ethInfo, bscInfo);
  await BackAndForthEvmToSolTest(ethInfo, solInfo);
  await BackAndForthEvmToSolTest(bscInfo, solInfo, true);
  await BackAndForthBaseRelayerTest(ethInfo, bscInfo);
}

async function BackAndForthBaseTest(
  chain1: EVMChainDetails,
  chain2: EVMChainDetails
) {
  console.log("Basic back and forth");

  const manager1 = NttManager__factory.connect(
    chain1.managerAddress,
    ETH_SIGNER
  );
  const manager2 = NttManager__factory.connect(
    chain2.managerAddress,
    BSC_SIGNER
  );

  const token1 = DummyToken__factory.connect(
    chain1.NTTTokenAddress,
    ETH_SIGNER
  );
  const token2 = DummyTokenMintAndBurn__factory.connect(
    chain2.NTTTokenAddress,
    BSC_SIGNER
  );

  const amount = utils.parseEther("1");
  await tryAndWaitThrice(() => token1.mintDummy(ETH_PUBLIC_KEY, amount));

  {
    // Send the cross-chain call
    await tryAndWaitThrice(() => token1.approve(chain1.managerAddress, amount));

    // cast call --rpc-url ws://eth-devnet2:8545 0x80EaE59c5f92F9f65338bba4F26FFC8Ca2b6224A "transfer(uint256,uint16,bytes32,bool,bytes)"  1000000000000000000 4 0x000000000000000000000000467fD9FEA4e77AC79504a23B45631D29e42eaa4A false 0x01000101 --from 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1
    const balanceManagerBeforeSend1 = await token1.balanceOf(
      chain1.managerAddress
    );
    const balanceUserBeforeSend1 = await token1.balanceOf(ETH_PUBLIC_KEY);

    const txResponse = await tryAndWaitThrice(() =>
      manager1["transfer(uint256,uint16,bytes32,bool,bytes)"](
        amount,
        chain2.chainId,
        addressToBytes32(ETH_PUBLIC_KEY),
        false,
        "0x01000101"
      )
    );

    const balanceManagerAfterSend1 = await token1.balanceOf(
      chain1.managerAddress
    );
    const balanceUserAfterSend1 = await token1.balanceOf(ETH_PUBLIC_KEY);
    if (!balanceManagerAfterSend1.eq(balanceManagerBeforeSend1.add(amount))) {
      console.log("Manager amount 1 incorrect");
    }

    if (!balanceUserAfterSend1.eq(balanceUserBeforeSend1.sub(amount))) {
      console.log("User amount 1 incorrect");
    }

    console.log("Finish initial transfer");

    const balanceBeforeRecv = await token2.balanceOf(ETH_PUBLIC_KEY);
    await receive(
      <ChainId>chain1.chainId,
      getEmitterAddressEth(chain1.transceiverAddress),
      parseSequenceFromLogEth(txResponse, chain1.wormholeCoreAddress),
      chain2
    );

    const balanceAfterRecv = await token2.balanceOf(ETH_PUBLIC_KEY);
    if (!balanceAfterRecv.eq(balanceBeforeRecv.add(amount))) {
      console.log("User amount 1 receive incorrect");
    }
    console.log("Finish initial receive");
  }

  {
    ///
    // Send the cross-chain call back to the original
    ///
    await tryAndWaitThrice(() => token2.approve(chain2.managerAddress, amount));

    const balanceManagerBeforeSend2 = await token2.balanceOf(
      chain1.managerAddress
    );
    const balanceUserBeforeSend2 = await token2.balanceOf(ETH_PUBLIC_KEY);

    const txResponse = await tryAndWaitThrice(() =>
      manager2["transfer(uint256,uint16,bytes32,bool,bytes)"](
        amount,
        chain1.chainId,
        addressToBytes32(ETH_PUBLIC_KEY),
        false,
        "0x01000101"
      )
    );
    console.log("Finish second transfer");

    const balanceManagerAfterSend2 = await token2.balanceOf(
      chain1.managerAddress
    );
    const balanceUserAfterSend2 = await token2.balanceOf(ETH_PUBLIC_KEY);
    if (!balanceManagerAfterSend2.eq(0) || !balanceManagerBeforeSend2.eq(0)) {
      console.log("Manager on burn chain has funds");
    }

    if (!balanceUserBeforeSend2.sub(amount).eq(balanceUserAfterSend2)) {
      console.log("User didn't transfer proper amount of funds on burn chain");
    }

    // Received the sent funds
    const balanceBeforeRecv = await token1.balanceOf(ETH_PUBLIC_KEY);
    await receive(
      <ChainId>chain2.chainId,
      getEmitterAddressEth(chain2.transceiverAddress),
      parseSequenceFromLogEth(txResponse, chain2.wormholeCoreAddress),
      chain1
    );
    console.log("Finish second receive");

    const balanceAfterRecv = await token1.balanceOf(ETH_PUBLIC_KEY);
    if (!balanceBeforeRecv.add(amount).eq(balanceAfterRecv)) {
      console.log("ReceiveMessage on back length failed");
    }
  }
}

async function BackAndForthEvmToSolTest(
  evmChain: EVMChainDetails,
  solChain: SolanaChainDetails,
  sourceBurn?: boolean
) {
  console.log(`EVM (${evmChain.chainId}) <> Solana back and forth`);

  const evmManager = NttManager__factory.connect(
    evmChain.managerAddress,
    evmChain.signer
  );
  const evmToken = (
    evmChain.chainName === "ethereum"
      ? DummyToken__factory
      : DummyTokenMintAndBurn__factory
  ).connect(evmChain.NTTTokenAddress, evmChain.signer);

  const amount = utils.parseEther("1");
  const scaledAmount = utils.parseUnits("1", 9);
  await tryAndWaitThrice(() => evmToken.mintDummy(ETH_PUBLIC_KEY, amount));

  const mintAddress = await SOL_NTT_CONTRACT.mintAccountAddress();
  const associatedTokenAddress = spl.getAssociatedTokenAddressSync(
    mintAddress,
    SOL_PUBLIC_KEY
  );
  const custodyAddress = await SOL_NTT_CONTRACT.custodyAccountAddress(
    mintAddress
  );

  {
    console.log(`Sending ${amount.toString()} (${scaledAmount.toString()})`);

    await tryAndWaitThrice(() =>
      evmToken.approve(evmChain.managerAddress, amount)
    );

    const balanceManagerBeforeSend1 = await evmToken.balanceOf(
      evmChain.managerAddress
    );
    const balanceUserBeforeSend1 = await evmToken.balanceOf(ETH_PUBLIC_KEY);

    const txResponse = await tryAndWaitThrice(() =>
      evmManager["transfer(uint256,uint16,bytes32,bool,bytes)"](
        amount,
        1,
        `0x${SOL_PUBLIC_KEY.toBuffer().toString("hex")}`,
        false,
        "0x01000101"
      )
    );

    const balanceManagerAfterSend1 = await evmToken.balanceOf(
      evmChain.managerAddress
    );
    const balanceUserAfterSend1 = await evmToken.balanceOf(ETH_PUBLIC_KEY);
    if (
      (sourceBurn && !balanceManagerAfterSend1.eq(BigNumber.from("0"))) ||
      !balanceManagerAfterSend1.eq(balanceManagerBeforeSend1.add(amount))
    ) {
      console.log("Manager amount 1 incorrect");
    }

    if (!balanceUserAfterSend1.eq(balanceUserBeforeSend1.sub(amount))) {
      console.log("User amount 1 incorrect");
    }

    console.log("Finish initial transfer");

    const balanceBeforeRecv = BigNumber.from(
      (await SOL_CONNECTION.getTokenAccountBalance(associatedTokenAddress))
        .value.amount
    );
    await receive(
      <ChainId>evmChain.chainId,
      getEmitterAddressEth(evmChain.transceiverAddress),
      parseSequenceFromLogEth(txResponse, evmChain.wormholeCoreAddress),
      solChain
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
    console.log("Finish initial receive");
  }

  {
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
      recipientChain: evmChain.chainName,
      recipientAddress: Buffer.from(
        addressToBytes32(ETH_PUBLIC_KEY).substring(2),
        "hex"
      ),
      shouldQueue: false,
    });
    console.log("Finish second transfer");

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

    // Received the sent funds
    const balanceBeforeRecv = await evmToken.balanceOf(ETH_PUBLIC_KEY);
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
    await receive(
      1,
      SOL_NTT_CONTRACT.emitterAccountAddress().toBuffer().toString("hex"),
      messageData.message.sequence.toString(),
      evmChain
    );
    console.log("Finish second receive");

    const balanceAfterRecv = await evmToken.balanceOf(ETH_PUBLIC_KEY);
    if (!balanceBeforeRecv.add(amount).eq(balanceAfterRecv)) {
      console.log("ReceiveMessage on back length failed");
    }
  }
}

// Relayer base calls
async function BackAndForthBaseRelayerTest(
  chain1: ChainDetails,
  chain2: ChainDetails
) {
  console.log("Basic back and forth on relayer");

  const manager1 = NttManager__factory.connect(
    chain1.managerAddress,
    ETH_SIGNER
  );
  const manager2 = NttManager__factory.connect(
    chain2.managerAddress,
    BSC_SIGNER
  );

  const token1 = DummyToken__factory.connect(
    chain1.NTTTokenAddress,
    ETH_SIGNER
  );
  const token2 = DummyTokenMintAndBurn__factory.connect(
    chain2.NTTTokenAddress,
    BSC_SIGNER
  );

  const amount = utils.parseEther("1");

  await tryAndWaitThrice(() => token1.mintDummy(ETH_PUBLIC_KEY, amount));

  {
    // Send the cross-chain call
    await tryAndWaitThrice(() => token1.approve(chain1.managerAddress, amount));

    console.log("Transfer with relayer from 2 to 4");
    const balanceUserBeforeSend = await token2.balanceOf(ETH_PUBLIC_KEY);

    const tx = await tryAndWaitThrice(() =>
      manager1["transfer(uint256,uint16,bytes32,bool,bytes)"](
        amount,
        chain2.chainId,
        addressToBytes32(ETH_PUBLIC_KEY),
        false,
        "0x01000100",
        { value: utils.parseEther("1") }
      )
    ); // with relayer
    console.log("sent!", tx.transactionHash, "waiting for relay...");

    // Wait for the relaying and VAA process to pick this up and transmit it.
    const log = getWormholeLog(
      tx,
      CONTRACTS.DEVNET.ethereum.core,
      addressToBytes32(RELAYER_CONTRACT).substring(2),
      0
    );
    const deliveryHash = await getDeliveryHashFromLog(
      log.log,
      2,
      ETH_SIGNER.provider,
      tx.blockHash
    );
    const wormholeRelayer = WormholeRelayer__factory.connect(
      RELAYER_CONTRACT,
      BSC_SIGNER.provider
    );
    let success = false;
    while (!success) {
      await delay(500);
      const successBlock = await wormholeRelayer.deliverySuccessBlock(
        deliveryHash
      );
      if (successBlock.gt("0")) {
        success = true;
      }
    }

    const balanceUserAfterSend = await token2.balanceOf(ETH_PUBLIC_KEY);
    if (!balanceUserBeforeSend.add(amount).eq(balanceUserAfterSend)) {
      console.log("User received a funky balance");
    }
  }

  {
    ///
    // Send the cross-chain call back
    ///
    await tryAndWaitThrice(() => token2.approve(chain2.managerAddress, amount));

    console.log("Transfer with relayer from 4 to 2");

    const balanceUserBeforeSend = await token1.balanceOf(ETH_PUBLIC_KEY);
    const tx = await tryAndWaitThrice(() =>
      manager2["transfer(uint256,uint16,bytes32,bool,bytes)"](
        amount,
        chain1.chainId,
        addressToBytes32(ETH_PUBLIC_KEY),
        false,
        "0x01000100",
        { value: utils.parseEther("1") }
      )
    ); // with relayer
    console.log("sent!", tx.transactionHash, "waiting for relay...");

    // Wait for the relaying and VAA process to pick this up and transmit it.
    const log = getWormholeLog(
      tx,
      CONTRACTS.DEVNET.bsc.core,
      addressToBytes32(RELAYER_CONTRACT).substring(2),
      0
    );
    const deliveryHash = await getDeliveryHashFromLog(
      log.log,
      4,
      BSC_SIGNER.provider,
      tx.blockHash
    );
    const wormholeRelayer = WormholeRelayer__factory.connect(
      RELAYER_CONTRACT,
      ETH_SIGNER.provider
    );
    let success = false;
    while (!success) {
      await delay(500);
      const successBlock = await wormholeRelayer.deliverySuccessBlock(
        deliveryHash
      );
      if (successBlock.gt("0")) {
        success = true;
      }
    }

    const balanceUserAfterSend = await token1.balanceOf(ETH_PUBLIC_KEY);
    if (!balanceUserBeforeSend.add(amount).eq(balanceUserAfterSend)) {
      console.log("User received a funky balance when relayed back");
    }

    console.log("Finished basic relayer call test");
  }
}

/*
Receive funds via collecting and submitting the VAA that we need to the endpoint to recvMessage.
*/
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

async function run() {
  // Deploy the stuff if not cached
  // Chain 1
  console.log("\nDeploying on eth-devnet");
  console.log("===============================================");
  const ethInfo = await deployEth(ETH_SIGNER, 2, "ethereum"); // Deploying on ETH

  // Chain 2
  console.log("\nDeploying on eth-devnet2");
  console.log("===============================================");
  const bscInfo = await deployEth(BSC_SIGNER, 4, "bsc"); // Deploying on the other network

  // Solana setup
  console.log("\nInitializing on solana-devnet");
  console.log("===============================================");
  const solInfo = await initSolana();

  // Put everything together so that calls work across chains
  await link(ethInfo, bscInfo, solInfo);

  await test(ethInfo, bscInfo, solInfo);
}

// Main function
run();

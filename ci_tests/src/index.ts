import {
  CONTRACTS,
  ChainId,
  getEmitterAddressEth,
  getSignedVAAWithRetry,
  parseSequenceFromLogEth,
} from "@certusone/wormhole-sdk";
import { WormholeRelayer__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts";
import {
  getDeliveryHashFromLog,
  getWormholeLog,
} from "@certusone/wormhole-sdk/lib/cjs/relayer";
import { Networkish } from "@ethersproject/networks";
import { NodeHttpTransport } from "@improbable-eng/grpc-web-node-http-transport";
import { Wallet, getDefaultProvider, utils } from "ethers";
import { existsSync, readFileSync, writeFileSync } from "fs";
import { DummyTokenMintAndBurn__factory } from "../evm_binding/factories/DummyToken.sol/DummyTokenMintAndBurn__factory";
import { DummyToken__factory } from "../evm_binding/factories/DummyToken.sol/DummyToken__factory";
import { ERC1967Proxy__factory } from "../evm_binding/factories/ERC1967Proxy__factory";
import { NttManager__factory } from "../evm_binding/factories/NttManager__factory";
import { TransceiverStructs__factory } from "../evm_binding/factories/TransceiverStructs__factory";
import { TrimmedAmountLib__factory } from "../evm_binding/factories/TrimmedAmount.sol/TrimmedAmountLib__factory";
import { WormholeTransceiver__factory } from "../evm_binding/factories/WormholeTransceiver__factory";

// Chain details to keep track of during the testing
interface ChainDetails {
  chainId: number;
  transceiverAddress: string;
  managerAddress: string;
  NTTTokenAddress: string;
  wormholeCoreAddress: string;
  rpcEndpoint: Networkish;
}

const ETH_PRIVATE_KEY =
  "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"; // Ganache default private key
const ETH_PUBLIC_KEY = "0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1";
const RELAYER_CONTRACT = "0x53855d4b64E9A3CF59A84bc768adA716B5536BC5";
async function deployEth(
  rpc_endpoint: string,
  chain_id: number
): Promise<ChainDetails> {
  // https://github.com/wormholelabs-xyz/example-queries-solana-stake-pool/blob/2f1199a5a70ecde90e8b8a47a4f9726da249d218/ts-test/mock.ts#L58
  const provider = getDefaultProvider(rpc_endpoint);
  const signer = new Wallet(ETH_PRIVATE_KEY, provider);

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
    //result = await NTTAddress.waitForDeployment();
    tokenSetting = 0; // Lock
  } else {
    console.log("Deploy burning NTT token");
    const ERC20BurningFactory = new DummyTokenMintAndBurn__factory(signer);
    NTTAddress = await ERC20BurningFactory.deploy();
    //result = await NTTAddress.waitForDeployment();
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
    86400 // Locking time
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
  const WormholetransceiverFactory = new WormholeTransceiver__factory(
    myObj,
    signer
  );
  const WormholeTransceiverAddress = await WormholetransceiverFactory.deploy(
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
  await (await manager.initialize()).wait();
  console.log("Initialize the transceiver");
  await (await transceiver.initialize()).wait();

  // Setup the initial calls, like transceivers for the manager
  console.log("Set transceiver for manager");
  await (await manager.setTransceiver(await transceiver.address)).wait();

  console.log("Set outbound limit for manager");
  await (await manager.setOutboundLimit(utils.parseEther("10000"))).wait();

  return {
    chainId: chain_id,
    transceiverAddress: await transceiverProxyAddress.address,
    managerAddress: await managerProxyAddress.address,
    NTTTokenAddress: ERC20NTTAddress,
    wormholeCoreAddress: "0xC89Ce4735882C9F0f0FE26686c53074E09B0D550", // Same on both of the chains
    rpcEndpoint: rpc_endpoint,
  };
}

async function link(chain1: ChainDetails, chain2: ChainDetails) {
  // Hook up all the important things together
  /*
    - Manager peer
    - Wormhole peer
    - inbound limits
    https://github.com/wormhole-foundation/example-native-token-transfers/blob/main/evm/test/IntegrationStandalone.t.sol
    */
  console.log("Starting linking process");
  console.log("========================");
  const provider1 = getDefaultProvider(<Networkish>chain1.rpcEndpoint);
  const signer1 = new Wallet(ETH_PRIVATE_KEY, provider1); // Ganache default private key

  const provider2 = getDefaultProvider(chain2.rpcEndpoint);
  const signer2 = new Wallet(ETH_PRIVATE_KEY, provider2); // Ganache default private key

  const manager1 = NttManager__factory.connect(
    <string>chain1.managerAddress,
    signer1
  );
  const manager2 = NttManager__factory.connect(
    <string>chain2.managerAddress,
    signer2
  );

  const transceiver1 = WormholeTransceiver__factory.connect(
    <string>chain1.transceiverAddress,
    signer1
  );
  const transceiver2 = WormholeTransceiver__factory.connect(
    <string>chain2.transceiverAddress,
    signer2
  );

  // Would make sense to store the 'client' with a generalized interface instead of the
  console.log("Set manager peers");
  await (
    await manager1.setPeer(
      chain2.chainId,
      addressToBytes32(chain2.managerAddress),
      18 // decimals
    )
  ).wait();
  await (
    await manager2.setPeer(
      chain1.chainId,
      addressToBytes32(chain1.managerAddress),
      18 // decimals
    )
  ).wait();

  console.log("Set wormhole Peers");
  await (
    await transceiver1.setWormholePeer(
      chain2.chainId,
      addressToBytes32(chain2.transceiverAddress)
    )
  ).wait();
  await (
    await transceiver2.setWormholePeer(
      chain1.chainId,
      addressToBytes32(chain1.transceiverAddress)
    )
  ).wait();

  console.log("Set inbound limits");
  await (
    await manager1.setInboundLimit(utils.parseEther("10000"), chain2.chainId)
  ).wait();
  await (
    await manager2.setInboundLimit(utils.parseEther("10000"), chain1.chainId)
  ).wait();

  console.log("Setting transceiver to be an EVM transceiver");
  await (await transceiver1.setIsWormholeEvmChain(chain2.chainId)).wait();
  await (await transceiver2.setIsWormholeEvmChain(chain1.chainId)).wait();

  console.log("Enable relaying");
  await (
    await transceiver1.setIsWormholeRelayingEnabled(chain2.chainId, true)
  ).wait();
  await (
    await transceiver2.setIsWormholeRelayingEnabled(chain1.chainId, true)
  ).wait();
  console.log("Finished linking!");

  // TODO - add Solana and other contracts in here
}

// Wormhole format means that addresses are bytes32 instead of addresses when using them to support other chains.
function addressToBytes32(address: string): string {
  return `0x000000000000000000000000${address.substring(2)}`;
}

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function test(chain1: ChainDetails, chain2: ChainDetails) {
  /*
    Tests to run 
    - Basic Move from A to B with balance checks
    - Corrupted or bad VAA usage
    - Relayer vs non-relayer path
    */
  const provider1 = getDefaultProvider(chain1.rpcEndpoint);
  const signer1 = new Wallet(ETH_PRIVATE_KEY, provider1); // Ganache default private key

  const provider2 = getDefaultProvider(chain2.rpcEndpoint);
  const signer2 = new Wallet(ETH_PRIVATE_KEY, provider2); // Ganache default private key

  const manager1 = NttManager__factory.connect(
    <string>chain1.managerAddress,
    signer1
  );
  const manager2 = NttManager__factory.connect(
    <string>chain2.managerAddress,
    signer2
  );

  const token1 = DummyToken__factory.connect(
    <string>chain1.NTTTokenAddress,
    signer1
  );
  const token2 = DummyTokenMintAndBurn__factory.connect(
    <string>chain2.NTTTokenAddress,
    signer2
  );

  console.log("Starting tests");
  console.log("========================");

  await BackAndForthBaseTest(chain1, chain2);
  await BackAndForthBaseRelayertest(chain1, chain2);
}

async function BackAndForthBaseTest(
  chain1: ChainDetails,
  chain2: ChainDetails
) {
  console.log("Basic back and forth");
  const provider1 = getDefaultProvider(chain1.rpcEndpoint);
  const signer1 = new Wallet(ETH_PRIVATE_KEY, provider1); // Ganache default private key

  const provider2 = getDefaultProvider(chain2.rpcEndpoint);
  const signer2 = new Wallet(ETH_PRIVATE_KEY, provider2); // Ganache default private key

  const manager1 = NttManager__factory.connect(
    <string>chain1.managerAddress,
    signer1
  );
  const manager2 = NttManager__factory.connect(
    <string>chain2.managerAddress,
    signer2
  );

  const token1 = DummyToken__factory.connect(
    <string>chain1.NTTTokenAddress,
    signer1
  );
  const token2 = DummyTokenMintAndBurn__factory.connect(
    <string>chain2.NTTTokenAddress,
    signer2
  );

  const amount = utils.parseEther("1");
  await (await token1.mintDummy(ETH_PUBLIC_KEY, amount)).wait();

  {
    // Send the crosschain call
    await (await token1.approve(chain1.managerAddress, amount)).wait();

    // cast call --rpc-url ws://eth-devnet2:8545 0x80EaE59c5f92F9f65338bba4F26FFC8Ca2b6224A "transfer(uint256,uint16,bytes32,bool,bytes)"  1000000000000000000 4 0x000000000000000000000000467fD9FEA4e77AC79504a23B45631D29e42eaa4A false 0x01000101 --from 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1
    const balanceManagerBeforeSend1 = await token1.balanceOf(
      chain1.managerAddress
    );
    const balanceUserBeforeSend1 = await token1.balanceOf(ETH_PUBLIC_KEY);

    await delay(5000);
    const txResponse = await (
      await manager1["transfer(uint256,uint16,bytes32,bool,bytes)"](
        amount,
        chain2.chainId,
        addressToBytes32(ETH_PUBLIC_KEY),
        false,
        "0x01000101"
      )
    ).wait();

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
    await receive(txResponse, chain1, chain2);

    const balanceAfterRecv = await token2.balanceOf(ETH_PUBLIC_KEY);
    if (!balanceAfterRecv.eq(balanceBeforeRecv.add(amount))) {
      console.log("User amount 1 receieve incorrect");
    }
    console.log("Finish initial receieve");
  }

  {
    ///
    // Send the crosschain call back to the original
    ///
    await (await token2.approve(chain2.managerAddress, amount)).wait();

    const balanceManagerBeforeSend2 = await token2.balanceOf(
      chain1.managerAddress
    );
    const balanceUserBeforeSend2 = await token2.balanceOf(ETH_PUBLIC_KEY);

    await delay(5000);
    const txResponse = await (
      await manager2["transfer(uint256,uint16,bytes32,bool,bytes)"](
        amount,
        chain1.chainId,
        addressToBytes32(ETH_PUBLIC_KEY),
        false,
        "0x01000101"
      )
    ).wait();
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
    await receive(txResponse, chain2, chain1);
    console.log("Finish second receieve");

    const balanceAfterRecv = await token1.balanceOf(ETH_PUBLIC_KEY);
    if (!balanceBeforeRecv.add(amount).eq(balanceAfterRecv)) {
      console.log("ReceiveMessage on back length failed");
    }
  }

  /*
    Sanity checks
        cast call <Manager Contract> "getThreshold()" --rpc-url ws://eth-devnet:8545
        cast call --rpc-url ws://eth-devnet:8545 0xC3Ef4965B788cc4b905084d01F2eb7D4b6E93ABF "transfer(uint256,uint16,bytes32,bool,bytes)" 1000000000000000000 1397 000000000000000000000000467fD9FEA4e77AC79504a23B45631D29e42eaa4A false 0x01010 --from 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1
        forge selectors list 

        cast call --rpc-url ws://eth-devnet:8545 0xC3Ef4965B788cc4b905084d01F2eb7D4b6E93ABF "transfer(uint256,uint16,bytes32,bool,bytes)" 1000000000000000000 1397 000000000000000000000000467fD9FEA4e77AC79504a23B45631D29e42eaa4A false 0x01000101 --from 0x90F8bf6A479f
320ead074411a4B0e7944Ea8c9C1
    
    Handling BAD errors...
    - According to the docs, Ganache returns the error slightly different than everything else. So, ethers.js doesn't know how to see the errors.
    - https://ethereum.stackexchange.com/questions/60731/assertionerror-error-message-must-contain-revert
    */
}

// Relayer base calls
async function BackAndForthBaseRelayertest(
  chain1: ChainDetails,
  chain2: ChainDetails
) {
  console.log("Basic back and forth on relayer");
  const provider1 = getDefaultProvider(chain1.rpcEndpoint);
  const signer1 = new Wallet(ETH_PRIVATE_KEY, provider1); // Ganache default private key

  const provider2 = getDefaultProvider(chain2.rpcEndpoint);
  const signer2 = new Wallet(ETH_PRIVATE_KEY, provider2); // Ganache default private key

  const manager1 = NttManager__factory.connect(
    <string>chain1.managerAddress,
    signer1
  );
  const manager2 = NttManager__factory.connect(
    <string>chain2.managerAddress,
    signer2
  );

  const token1 = DummyToken__factory.connect(
    <string>chain1.NTTTokenAddress,
    signer1
  );
  const token2 = DummyTokenMintAndBurn__factory.connect(
    <string>chain2.NTTTokenAddress,
    signer2
  );

  const amount = utils.parseEther("1");

  await (await token1.mintDummy(ETH_PUBLIC_KEY, amount)).wait();

  {
    // Send the crosschain call
    await (await token1.approve(chain1.managerAddress, amount)).wait();

    console.log("Transfer with relayer from 2 to 4");
    const balanceUserBeforeSend = await token2.balanceOf(ETH_PUBLIC_KEY);

    await delay(10000);
    const tx = await (
      await manager1["transfer(uint256,uint16,bytes32,bool,bytes)"](
        amount,
        chain2.chainId,
        addressToBytes32(ETH_PUBLIC_KEY),
        false,
        "0x01000100",
        { value: utils.parseEther("1") }
      )
    ).wait(); // with relayer
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
      provider1,
      tx.blockHash
    );
    const wormholeRelayer = WormholeRelayer__factory.connect(
      RELAYER_CONTRACT,
      provider2
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
    // Send the crosschain call back
    ///
    await (await token2.approve(chain2.managerAddress, amount)).wait();

    console.log("Transfer with relayer from 4 to 2");

    const balanceUserBeforeSend = await token1.balanceOf(ETH_PUBLIC_KEY);
    await delay(10000);
    const tx = await (
      await manager2["transfer(uint256,uint16,bytes32,bool,bytes)"](
        amount,
        chain1.chainId,
        addressToBytes32(ETH_PUBLIC_KEY),
        false,
        "0x01000100",
        { value: utils.parseEther("1") }
      )
    ).wait(); // with relayer
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
      provider2,
      tx.blockHash
    );
    const wormholeRelayer = WormholeRelayer__factory.connect(
      RELAYER_CONTRACT,
      provider1
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
async function receive(txResponse, chainSend, chainDest) {
  const provider = getDefaultProvider(chainDest.rpcEndpoint);
  const signer = new Wallet(ETH_PRIVATE_KEY, provider); // Ganache default private key

  const sequence = await parseSequenceFromLogEth(
    txResponse,
    CONTRACTS.DEVNET.ethereum.core
  );

  // Turn into bytes32 from standard ETH address I'm guessing
  const emitterAddress = getEmitterAddressEth(chainSend.transceiverAddress);

  // poll until the guardian(s) witness and sign the vaa
  const { vaaBytes: signedVAA } = await getSignedVAAWithRetry(
    ["http://guardian:7071"], // HTTP host for the Guardian
    <ChainId>chainSend.chainId,
    emitterAddress,
    sequence,
    {
      transport: NodeHttpTransport(),
    }
  );

  // Send the VAA to the transceiver that needs it
  const transceiver = WormholeTransceiver__factory.connect(
    <string>chainDest.transceiverAddress,
    signer
  );
  return (await transceiver.receiveMessage(signedVAA)).wait();
}

async function run() {
  const rpc_endpoint1 = "http://eth-devnet:8545";
  const rpc_endpoint2 = "http://eth-devnet2:8545";

  let infoChain1;
  let infoChain2;

  if (existsSync("./chain_info.json")) {
    console.log("Using cached run!");
    const data = require("./chain_info.json");
    infoChain1 = <ChainDetails>data["infoChain1"];
    infoChain2 = <ChainDetails>data["infoChain2"];
    console.log(data);
  } else {
    // Deploy the stuff if not cached
    // Chain 1
    console.log("Deploying on eth-devnet");
    console.log("===============================================");
    infoChain1 = await deployEth(rpc_endpoint1, 2); // Deploying on ETH

    // Chain 2
    console.log("Deploying on eth-devnet2");
    console.log("===============================================");
    infoChain2 = await deployEth(rpc_endpoint2, 4); // Deploying on the other network

    const cached_entry = { infoChain1: infoChain1, infoChain2: infoChain2 };

    // Write to file
    await writeFileSync("./chain_info.json", JSON.stringify(cached_entry));

    // Put everything together so that calls work across chains
    await link(infoChain1, infoChain2);
  }

  await test(infoChain1, infoChain2);
}

// Main function
run();

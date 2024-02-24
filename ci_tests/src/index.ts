import { AddressLike, Networkish, Network, Wallet, getDefaultProvider, id, BytesLike, parseEther} from "ethers";

import {Manager__factory} from "../evm_binding/factories/Manager__factory";
import {EndpointStructs__factory} from "../evm_binding/factories/EndpointStructs__factory";
import {NormalizedAmountLib__factory} from "../evm_binding/factories/NormalizedAmount.sol/NormalizedAmountLib__factory";
import {ERC1967Proxy__factory} from "../evm_binding/factories/ERC1967Proxy__factory";
import {MockWormholeEndpointContract__factory} from "../evm_binding/factories/MockEndpoints.sol/MockWormholeEndpointContract__factory"
import {DummyTokenMintAndBurn__factory} from "../evm_binding/factories/DummyToken.sol/DummyTokenMintAndBurn__factory";
import {DummyToken__factory} from "../evm_binding/factories/DummyToken.sol/DummyToken__factory";
import {writeFileSync, readFileSync, existsSync} from "fs";

// Chain details to keep track of during the testing
interface ChainDetails {
    chainId: number,
    endpointAddress: AddressLike,
    managerAddress: AddressLike, 
    NTTTokenAddress: AddressLike,
    wormholeCoreAddress: AddressLike,
    rpcEndpoint: Networkish
}

interface StoredJSON {
    infoChain1: ChainDetails,
    infoChain2: ChainDetails
}

const ETH_PRIVATE_KEY = "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d";
async function deployEth(rpc_endpoint: string, chain_id: number) : Promise<ChainDetails> {
    var result; 
    // https://github.com/wormholelabs-xyz/example-queries-solana-stake-pool/blob/2f1199a5a70ecde90e8b8a47a4f9726da249d218/ts-test/mock.ts#L58
    const provider = getDefaultProvider(rpc_endpoint);
    const signer = new Wallet(ETH_PRIVATE_KEY, provider); // Ganache default private key

    // Deploy libraries used by various things
    console.log("Deploying libraries of endpointStructs and normalizedAmounts");
    const endpointStructsFactory = new EndpointStructs__factory(signer);
    const endpointStructsContract = await endpointStructsFactory.deploy();
    result = await endpointStructsContract.waitForDeployment();
    
    const normalizedAmountFactory = new NormalizedAmountLib__factory(signer);
    const normalizedAmountContract = await normalizedAmountFactory.deploy();
    result = await normalizedAmountContract.waitForDeployment();

    // Deploy the NTT token 
    var NTTAddress;
    var tokenSetting;
    if(chain_id == 1){
        console.log("Deploy locking NTT token");
        const ERC20LockingFactory = new DummyToken__factory(signer);
        NTTAddress = await ERC20LockingFactory.deploy();
        result = await NTTAddress.waitForDeployment();
        tokenSetting = 0; // Lock
    } else{
        console.log("Deploy locking NTT token");
        const ERC20BurningFactory = new DummyTokenMintAndBurn__factory(signer);
        NTTAddress = await ERC20BurningFactory.deploy();
        result = await NTTAddress.waitForDeployment();
        tokenSetting = 1; // Burn
    }

    const endpointStructsAddress = await endpointStructsContract.getAddress();
    const normalizedAmountAddress = await normalizedAmountContract.getAddress();
    const ERC20NTTAddress = await NTTAddress.getAddress();

    let myObj = {
        "src/libraries/EndpointStructs.sol:EndpointStructs" : endpointStructsAddress,
        "src/libraries/NormalizedAmount.sol:NormalizedAmountLib" : normalizedAmountAddress
    }

    // https://github.com/search?q=repo%3Awormhole-foundation%2Fwormhole-connect%20__factory&type=code
    // https://github.com/wormhole-foundation/wormhole/blob/00f504ef452ae2d94fa0024c026be2d8cf903ad5/clients/js/src/evm.ts#L335
    console.log("Deploying manager implementation");
    const wormholeManager = new Manager__factory(myObj, signer);
    const managerAddress = await wormholeManager.deploy(
        ERC20NTTAddress, // Token address
        tokenSetting, // Lock
        chain_id, // chain id
        86400 // Locking time 
    )
    result = await managerAddress.waitForDeployment();

    console.log("Deploying manager proxy");
    await delay(2000); // Fixing race condition on nonce. Need to figure out why 'waitForDeployment()' does this?
    const ERC1967ProxyFactory = new ERC1967Proxy__factory(signer);
    const managerProxyAddress = await ERC1967ProxyFactory.deploy(await managerAddress.getAddress(), "0x");
    result = await managerProxyAddress.waitForDeployment();

    // // After we've deployed the proxy AND the manager then connect to the proxy with the interface of the manager.
    const manager = Manager__factory.connect(await managerProxyAddress.getAddress(), signer);

    console.log("Deploy endpoint implementation");
    const WormholeEndpointFactory = new MockWormholeEndpointContract__factory(myObj, signer);
    const WormholeEndpointAddress = await WormholeEndpointFactory.deploy(
        // List of useful wormhole contracts - https://github.com/wormhole-foundation/wormhole/blob/00f504ef452ae2d94fa0024c026be2d8cf903ad5/ethereum/ts-scripts/relayer/config/ci/contracts.json
        await manager.getAddress(),
        "0xC89Ce4735882C9F0f0FE26686c53074E09B0D550", // Core wormhole contract - https://docs.wormhole.com/wormhole/blockchain-environments/evm#local-network-contract -- may need to be changed to support other chains
        "0x53855d4b64E9A3CF59A84bc768adA716B5536BC5", //"0xE66C1Bc1b369EF4F376b84373E3Aa004E8F4C083", // Relayer contract -- double check these...
        "0x0000000000000000000000000000000000000000", // TODO - Specialized relayer?????? 
        200 // Consistency level
    );
    result = await WormholeEndpointAddress.waitForDeployment();
    
    // // Setup with the proxy
    console.log("Deploy endpoint proxy");
    await delay(2000); // Fixing race condition on nonce. Need to figure out why 'waitForDeployment()' does this?
    const endpointProxyFactory = new ERC1967Proxy__factory(signer);
    const endpointProxyAddress = await endpointProxyFactory.deploy(await WormholeEndpointAddress.getAddress(), "0x");
    result = await endpointProxyAddress.waitForDeployment();
    const endpoint = MockWormholeEndpointContract__factory.connect(await endpointProxyAddress.getAddress(), signer);

    // initialize() on both the manager and endpoint
    console.log("Initialize the manager");
    result = await manager.initialize();
    console.log("Initialize the endpoint");
    await delay(2000); // Fixing race condition on nonce. Need to figure out why 'waitForDeployment()' does this?
    result = await endpoint.initialize();

    // Setup the initial calls, like endpoints for the manager
    console.log("Set endpoint for manager");
    await delay(2000); // Fixing race condition on nonce. Need to figure out why 'waitForDeployment()' does this?
    result = await manager.setEndpoint(await endpoint.getAddress());
    result.wait();

    console.log("Set outbound limit for manager");
    await delay(2000); // Fixing race condition on nonce. Need to figure out why 'waitForDeployment()' does this?
    result = await manager.setOutboundLimit(parseEther("10000"));
    result.wait();

    return {
        chainId: chain_id,
        endpointAddress : (await endpointProxyAddress.getAddress()),
        managerAddress: (await managerProxyAddress.getAddress()),
        NTTTokenAddress: ERC20NTTAddress,
        wormholeCoreAddress: "0xC89Ce4735882C9F0f0FE26686c53074E09B0D550", // Same on both of the chains
        rpcEndpoint: rpc_endpoint
    }
}

async function link(chain1: ChainDetails, chain2: ChainDetails){
    // Hook up all the important things together
    var result; 
    /*
    - Manager Sibling
    - Wormhole sibling
    - inbound limits
    https://github.com/wormhole-foundation/example-native-token-transfers/blob/main/evm/test/IntegrationStandalone.t.sol
    */
    console.log("Starting linking process");
    console.log("========================")
    const provider1 = getDefaultProvider(chain1.rpcEndpoint);
    const signer1 = new Wallet(ETH_PRIVATE_KEY, provider1); // Ganache default private key

    const provider2 = getDefaultProvider(chain2.rpcEndpoint);
    const signer2 = new Wallet(ETH_PRIVATE_KEY, provider2); // Ganache default private key

    const manager1 = Manager__factory.connect(<string>chain1.managerAddress, signer1);
    const manager2 = Manager__factory.connect(<string>chain2.managerAddress, signer2);

    const endpoint1 = MockWormholeEndpointContract__factory.connect(<string>chain1.endpointAddress, signer1);
    const endpoint2 = MockWormholeEndpointContract__factory.connect(<string>chain2.endpointAddress, signer2);

    // Would make sense to store the 'client' with a generalized interface instead of the 
    console.log("Set manager siblings");
    result = await manager1.setSibling(chain2.chainId, <BytesLike>addressToBytes(<string>chain2.managerAddress));
    result.wait();
    await delay(2000); // Fixing race condition on nonce. Need to figure out why 'waitForDeployment()' does this?
    result = await manager2.setSibling(chain1.chainId, <BytesLike>addressToBytes(<string>chain1.managerAddress));
    result.wait();

    console.log("Set wormhole siblings")
    result = await endpoint1.setWormholeSibling(chain2.chainId, <BytesLike>addressToBytes(<string>chain2.endpointAddress))
    result.wait();
    await delay(2000); // Fixing race condition on nonce. Need to figure out why 'waitForDeployment()' does this?
    result = await endpoint2.setWormholeSibling(chain1.chainId, <BytesLike>addressToBytes(<string>chain1.endpointAddress))
    result.wait();
    
    console.log("Set inbound limits");
    result = await manager1.setInboundLimit(parseEther("10000"), chain2.chainId);
    result.wait();
    await delay(2000);
    result = await manager2.setInboundLimit(parseEther("10000"), chain1.chainId);
    result.wait();

    console.log("Setting endpoint to be an EVM endpoint");
    result = await endpoint1.setIsWormholeEvmChain(chain2.chainId);
    result.wait();
    await delay(2000);
    result = await endpoint2.setIsWormholeEvmChain(chain1.chainId);
    result.wait();
    await delay(2000);

    console.log("Enable relaying");
    result = await endpoint1.setIsWormholeRelayingEnabled(chain2.chainId, true);
    result.wait();
    result = await endpoint2.setIsWormholeRelayingEnabled(chain1.chainId, true);
    result.wait();
    console.log("Finished linking!");
}

// Wormhole format means that addresses are bytes32 instead of addresses when using them to support other chains.
function addressToBytes(address: String) : String {
    var address_arr = address.split("");    
    var new_address = "0x000000000000000000000000" + address_arr.slice(2,10000).join("") 
    return new_address;
}

function delay(ms: number) {
    return new Promise( resolve => setTimeout(resolve, ms) );
}

async function test(chain1: ChainDetails, chain2: ChainDetails){
    /*
    Tests to run 
    - Basic Move from A to B with balance checks
    - Corrupted or bad VAA usage
    - Relayer vs non-relayer path
    */
    var result;
    const provider1 = getDefaultProvider(chain1.rpcEndpoint);
    const signer1 = new Wallet(ETH_PRIVATE_KEY, provider1); // Ganache default private key

    const provider2 = getDefaultProvider(chain2.rpcEndpoint);
    const signer2 = new Wallet(ETH_PRIVATE_KEY, provider2); // Ganache default private key

    const manager1 = Manager__factory.connect(<string>chain1.managerAddress, signer1);
    const manager2 = Manager__factory.connect(<string>chain2.managerAddress, signer2);

    const token1 = DummyToken__factory.connect(<string>chain1.NTTTokenAddress, signer1);
    const token2 = DummyTokenMintAndBurn__factory.connect(<string>chain2.NTTTokenAddress, signer2);

    console.log("Starting tests");
    console.log("========================")

    // TODO - do I need to encode this to use the transfer specifically?
    var amount = parseEther("1");
    result = await token1.mintDummy("0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1", amount);
    result.wait();
    await delay(10000);

    console.log("NTT token balance: ", await token1.balanceOf("0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1"));
 
    console.log("Approving transfer");

    // Send the crosschain call
    await token1.approve(chain1.managerAddress, amount);
    result.wait();
    await delay(20000);

    console.log("Sending transfer");
    // cast call --rpc-url ws://eth-devnet:8545 0xC3Ef4965B788cc4b905084d01F2eb7D4b6E93ABF "transfer(uint256,uint16,bytes32,bool,bytes)" 1000000000000000000 1397 000000000000000000000000467fD9FEA4e77AC79504a23B45631D29e42eaa4A false 0x01000101 --from 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1
    //result = await manager1["transfer(uint256,uint16,bytes32)"](amount, chain2.chainId, <BytesLike>addressToBytes(<string>chain2.managerAddress));

    // cast call --rpc-url ws://eth-devnet:8545 0xFD3C3E25E7E30921Bf1B4D1D55fbb97Bc43Ac8B8 "transfer(uint256,uint16,bytes32,bool,bytes)"  1000000000000000000 1397 0x000000000000000000000000467fD9FEA4e77AC79504a23B45631D29e42eaa4A true 0x01000101 --from 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1
    // result = await manager1["transfer(uint256,uint16,bytes32,bool,bytes)"](amount, chain2.chainId, <BytesLike>addressToBytes(<string>chain2.managerAddress), false, "0x01000101"); // No relayer - actually works but don't know how to get info from the spy.

    //cast call --rpc-url ws://eth-devnet:8545 0xFD3C3E25E7E30921Bf1B4D1D55fbb97Bc43Ac8B8 "transfer(uint256,uint16,bytes32,bool,bytes)"  1000000000000000000 1397 0x000000000000000000000000467fD9FEA4e77AC79504a23B45631D29e42eaa4A true 0x01000100 --from 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1
    result = await manager1["transfer(uint256,uint16,bytes32,bool,bytes)"](amount, chain2.chainId, <BytesLike>addressToBytes(<string>chain2.managerAddress), false, "0x01000100", {value: parseEther('1')}); // with relayer


    await delay(20000);
    var txResponse = await result.wait();
    console.log("NTT token balance of manager contract: ", await token1.balanceOf(chain1.managerAddress));

    console.log("Query chain 2");
    console.log("NTT token balance on new chain if relayed: ", await token2.balanceOf("0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1"));


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

async function run(){

    const rpc_endpoint1 = "ws://eth-devnet:8545";
    const rpc_endpoint2 = "ws://eth-devnet2:8545";

    // TODO - find a way to cache this data :) 
    var infoChain1;
    var infoChain2; 

    if(existsSync("./chain_info.json")){
        console.log("Using cached run!");
        var data = JSON.parse(readFileSync('./chain_info.json').toString('utf-8', 0, 1000000000000000));
        infoChain1 = <ChainDetails>data['infoChain1'];
        infoChain2 = <ChainDetails>data['infoChain2'];
        console.log(data);
    }else{ // Deploy the stuff if not cached
        // Chain 1
        console.log("Deploying on eth-devnet");
        console.log("===============================================");
        infoChain1 = await deployEth(rpc_endpoint1 , 1); // Deploying on ETH

        // Chain 2
        console.log("Deploying on eth-devnet2");
        console.log("===============================================");
        infoChain2 = await deployEth(rpc_endpoint2 , 1397); // Deploying on the other network

        var cached_entry = {"infoChain1" : infoChain1 , "infoChain2" : infoChain2}

        // Write to file
        await writeFileSync("./chain_info.json", JSON.stringify(cached_entry) );

        // Put everything together so that calls work across chains
        await link(infoChain1, infoChain2);
    }

    // TODO - call interactive tests
    // Maybe have a flag to turn this on or off for a DEBUG env?
    await test(infoChain1, infoChain2);
}

// Main function
run();
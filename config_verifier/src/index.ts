
import fs from "fs";
import { NttManager__factory } from "../../ci_tests/evm_binding/factories/NttManager__factory"
import { WormholeTransceiver__factory } from "../../ci_tests/evm_binding/factories/WormholeTransceiver__factory"

import { BigNumber, ethers, providers } from "ethers";
import { keccak256 } from "@certusone/wormhole-sdk";
import {NTT} from "../../solana/ts/sdk/ntt";
import {web3 } from "@coral-xyz/anchor";
import { BN, translateError, type IdlAccounts, Program } from '@coral-xyz/anchor'
import { PublicKey, PublicKeyInitData } from "@solana/web3.js";
import * as base58 from "bs58";

import {
    Layout,
    CustomConversion,
    encoding,
    ChainId,
  } from "@wormhole-foundation/sdk-base";
import { type ExampleNativeTokenTransfers as RawExampleNativeTokenTransfers } from '../../solana/target/types/example_native_token_transfers'
import * as spl from "@solana/spl-token";

type OmitGenerics<T> = {
    [P in keyof T]: T[P] extends Record<"generics", any>
    ? never
    : T[P] extends object
    ? OmitGenerics<T[P]>
    : T[P];
  };
  
export type ExampleNativeTokenTransfers = OmitGenerics<RawExampleNativeTokenTransfers>
export type Config = IdlAccounts<ExampleNativeTokenTransfers>['config']

async function getConfig(config?: Config): Promise<Config> {
    return config ?? await this.program.account.config.fetch(this.configAccountAddress())
}

async function calcLocation(slot, index ){
    return BigNumber.from(keccak256(slot)).add(index);
}

type Seed = Uint8Array | string;
function derivePda(
    seeds: Seed | readonly Seed[],
    programId: PublicKeyInitData
  ) {
    const toBytes = (s: string | Uint8Array) => typeof s === "string" ? encoding.bytes.encode(s) : s;
    return PublicKey.findProgramAddressSync(    
      Array.isArray(seeds) ? seeds.map(toBytes) : [toBytes(seeds as Seed)],
      new PublicKey(programId),
    )[0];
    }

function getChainIds(chains) {
    let arr = [];
    for (const index in chains){
        const chain = chains[index]
        arr.push(chain['chainId']);
    }
    return arr;
}

async function configureChains(){
    const chainFile = fs.readFileSync(`./src/config.json`);
    const chains = JSON.parse(chainFile.toString());
    const chainIdList = getChainIds(chains['chains']);

    var configurationData = {};
    for (const chain of chains['chains']){
        console.log(`Getting configuration for chain - ${chain['description']}(${chain['chainId']})`)
        var rpc = chain['rpc'];
        var managerAddress = chain["managerAddress"];
        if(chain['networkType'] == 'evm'){
            var data = await configureEvm(rpc, managerAddress);
            data['type'] = chain['networkType'];
            data['chainId'] = chain['chainId'];
            configurationData[chain['chainId']] = data; 
        }
        else if(chain['networkType'] == 'solana'){
            var data = await configureSolana(rpc, managerAddress, chainIdList, chain['chainId']);
            data['chainId'] = chain['chainId'];
            data['type'] = chain['networkType'];
            configurationData[chain['chainId']] = data; 
            //process.exit()
        }
        else {
            console.log("Not supported!");
        }
    }

    return configurationData;
}

async function configureSolana(rpc, managerAddress, chainIdList, chainId){
    const managerData = {}; 

    const SOL_CONNECTION = new web3.Connection(
        rpc,
        "confirmed"
    );

    // Devnet configuration....
    const fromHexString = (hexString) => Uint8Array.from(hexString.match(/.{1,2}/g).map((byte) => parseInt(byte, 16)));
    managerData['managerAddress'] = managerAddress;
    const manager = new NTT(SOL_CONNECTION, {
        nttId: base58.encode(fromHexString(managerAddress.substring(2))),
        wormholeId: "3u8hJUVTA4jH1wYAyUur7FFZVQ8H635K3tSHHF4ssjQ5",
      });


    var to_public_key = new web3.PublicKey(
        base58.encode(fromHexString(managerAddress.substring(2)))
    );
    // var accounts = await SOL_CONNECTION.getProgramAccounts(to_public_key, {filters: [{
    //     memcmp: {
    //         offset: 0,
    //         bytes: base58.encode([231, 104, 182, 96, 168, 43, 216, 20])
    //     }
    // }]});

    // console.log(accounts);
    // //console.log(accounts.length)
    // console.log(await manager.program.account.registeredTransceiver.fetch(accounts[0].pubkey));
    const managerConfig = await manager.getConfig();

    managerData['mode'] = (managerConfig['mode'].locking == undefined ? 1 : 0); // Convert to an integer for later use
    managerData['token'] = managerConfig['tokenProgram']
    managerData['threshold'] = managerConfig['threshold'].valueOf() // The 'threshold' value
    managerData['count'] = managerConfig.enabledTransceivers; // Amount of active transceivers
    
    // https://spl.solana.com/token#example-creating-your-own-fungible-token
    const mintInfo = await spl.getMint(
        SOL_CONNECTION,
        managerConfig['mint'],
        'finalized',
      );
        
    managerData['token'] = "0x" + bufferToHex(managerConfig['mint'].toBuffer()); 
    managerData['tokenDecimals'] = mintInfo['decimals'];


    managerData['outboundRateLimit'] = (await manager.program.account.outboxRateLimit.fetch(manager.outboxRateLimitAccountAddress()))['rateLimit']['limit'];

    var solana_emitter = manager.emitterAccountAddress();
    var transceiver_address_buffer = "0x" + bufferToHex(solana_emitter.toBuffer());

    /*
    This information is much different than the EVM.
        - Manager is the same as the transceiver on Solana. Only support for a single transceiver. So, I feel safe setting the 'managerAddress'
        - The 'emitter account' is the actual emitter that we need to use. I am getting the address of this account and using this.
        - Consistency level is hardcoded on the Solana side to be 'finalized'. So, just hardcoding that here
    */
    managerData['transceivers'] = [{ 
        address: transceiver_address_buffer, isWormhole: true, consistencyLevel: 1, nttManager: managerAddress
    }];
    managerData['manager'] = manager;

    return managerData;
}

async function configureEvm(rpc, managerAddress){
    const provider = new providers.JsonRpcProvider(rpc);

    const managerData = {}; 
    const signer = new ethers.VoidSigner("0x8ba1f109551bD432803012645Ac136ddd64DBA72", provider); // Actual address doesn't matter since we're a VOID signer
    managerData['signer'] = signer; 

    const Manager = await NttManager__factory.connect(managerAddress, signer);
    managerData['manager'] = Manager; 
    managerData['managerAddress'] = managerAddress;

    var threshold = await Manager.getThreshold();
    var mode = await Manager.getMode();
    var token = await Manager.token();
    var decimals = await Manager.tokenDecimals();
    var outboundRateLimit = (await Manager.getOutboundLimitParams())['limit']
    managerData['mode'] = mode; 
    managerData['token'] = token; 
    managerData['threshold'] = threshold;
    managerData['tokenDecimals'] = decimals;
    managerData['outboundRateLimit'] = outboundRateLimit;

    var transceivers = await Manager.getTransceivers();

    // Get the creation bytecode of the contract to verify we've deployed the proper thing
    // https://eips.ethereum.org/EIPS/eip-1967
    // var implementationAddress = await provider.getStorageAt(managerAddress, "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc")

    // Get the transeivers in storage based upon the storage setup that we found
    // Take a hash of the slot then add the index to find the slot of the transceiver
    var transceiverList = [];
    for (var i = 0; i < transceivers.length; i++){
        var transceiverAddress = transceivers[i];

        // Check to see if it's a wormhole transeiver or not
        const transceiver = await WormholeTransceiver__factory.connect(transceiverAddress, provider);

        // If it's a wormchain, then setup all of the necessary wormhole specific checks
        var isWormhole = false;
        try {

            // If this succeeds, then it's a wormhole transeiver
            await transceiver.getWormholePeer(1);
            isWormhole = true;

            var consistencyLevel = await transceiver.consistencyLevel();
            var nttManager = await transceiver.nttManager();

            // Only going to operate on a transceiver that we know. 
            transceiverList.push({address: transceiverAddress, isWormhole: isWormhole, transceiver: transceiver, consistencyLevel: consistencyLevel, nttManager: nttManager});

            break;
        }
        catch{} // defaults to not adding it
    }

    managerData['transceivers'] = transceiverList;
    return managerData;
}

/*
Check the following: 
- Each chain ID corresponds to the expected peer for Wormhole
- Each decimal corresponds to the expected peer for Wormhole
- Each chain ID has the proper manager to the expected peer
*/
async function checkWormholeTranseivers(chainData){
 
    console.log("Checking transceiver configurations....");
    for(var target_id in chainData){
        for (var src_id in chainData){

            var target = chainData[target_id];
            var src = chainData[src_id];
            if(target['chainId'] == src['chainId']){
                // One time checks for when they match 

                //// Consistency Level check
                //// Turn off check for testnet...
                if(target['transceivers'][0]['consistencyLevel'] == 200 || target['transceivers'][0]['consistencyLevel'] == 201){
                     console.log(`WARNING: Non-final consistency level for transceiver: ${target['transceivers'][0]['address'].toHexString()}-${target_id}`);
                }

                // Check the transeiver ownership. Important for sending and receiving messages
                if(target['transceivers'][0]['nttManager'] != target['managerAddress']){
                    console.log(`ERROR: Transceiver inconsistent NTTManager Ownership: ${target['transceivers'][0]['address']}-${target_id}`); 
                }

                continue;
            }

            // Chain specific code here for finding the peer that we need
            var targetPeerAddress;

            if(target['type'] == 'evm'){
                targetPeerAddress = BigNumber.from(await target['transceivers'][0]['transceiver'].getWormholePeer(src['chainId']));
            }
            else if(target['type'] == 'solana'){
                try{
                    targetPeerAddress = await target['manager'].program.account.transceiverPeer.fetch(target['manager'].transceiverPeerAccountAddress(src['chainId']))
                    targetPeerAddress = BigNumber.from("0x" + bufferToHex( targetPeerAddress['address']));
                }
                catch(err){
                    console.log("Error in checkWormholeTransceiver Solana:", err);
                    targetPeerAddress = BigNumber.from(0x000000000000000000000000000000000000000000000); // Can't find the addresss, since it doesn't exist
                }
            }else{
                console.log("Invaild chain type in checkTransceivers");
            }

            if(!targetPeerAddress.eq(src['transceivers'][0]['address'])){
                console.log(`ERROR: Peers don't match chain id for sender chain ${target_id} and receiving chain ${src_id}`);
            }
        }
    }
    console.log("Finishing transceiver configurations....");

}

function bufferToHex (buffer) {
    return [...new Uint8Array (buffer)]
        .map (b => b.toString (16).padStart (2, "0"))
        .join ("");
}

/*
Check the various chain setups corresponding to each other. 
What is currently checked:
- Manager peer registration
- Decimals 
- Burn/lock bridge configuration
- Threshold is maxed out
- Inbound rate limit
- Outbound rate limit
*/
async function checkManagers(chainData){

    console.log("Checking manager configurations....");

    var burn = 0;
    var lock = 0;
    for(var target_id in chainData){
        for (var src_id in chainData){

            var target = chainData[target_id];
            var src = chainData[src_id];

            if(target['chainId'] == src['chainId']){

                // Mode check
                if(target['mode'] == 1){
                    burn += 1;
                }
                else if(target['mode'] == 0){
                    lock += 1;
                }
                else{
                    console.log(`ERROR: Invalid mode for chain ${target_id}`)
                }

                // Threshold check to ensure its the maximum that it can be. 
                if(target['threshold'] < target['count']){
                    console.log(`WARNING: NTT Manager has lower threshold than registered transceivers. ChainID - ${target_id}`); 
                }

                // Check if the rate limit is turned off or maxed out
                if(target['outboundRateLimit'].eq(0) || target['outboundRateLimit'].eq(BigNumber.from(2).pow(256).sub(1))){
                    console.log(`WARNING: Outbound rate limit disabled or very high. ChainID - ${target_id}`); 
                }
                continue; 
            }

            // Get the peer information of the manager
            var targetPeerInformation = {}; 
            if(target['type'] == 'evm'){
                targetPeerInformation = await target['manager'].getPeer(src['chainId']);
            }else if(target['type'] == 'solana'){
                var targetPeerInformationTmp = await target['manager'].program.account.nttManagerPeer.fetch(target['manager'].peerAccountAddress(src['chainId']));
                
                targetPeerInformation['peerAddress'] = "0x" + bufferToHex(targetPeerInformationTmp['address'])
                targetPeerInformation['tokenDecimals'] = targetPeerInformationTmp['tokenDecimals'];
            }else{
                console.log("Invalid chain type...");
            }

            // Ensure that the peers match up between the target and destination
            if(!BigNumber.from(targetPeerInformation['peerAddress']).eq(src['managerAddress'])){
                console.log(`ERROR: Peers don't match chain id for manager sender chain ${target_id} and receiving chain ${src_id}`);
            }

            // Check that the decimals for the configuration match up with the other chains decimals
            if(targetPeerInformation['tokenDecimals'] != src['tokenDecimals']){
                console.log(`ERROR: Peers don't match decimals for sender chain ${target_id} with decimals ${targetPeerInformation['tokenDecimals']} and receiving chain ${src_id} with decimals ${src['tokenDecimals']}`);
            }  

            if(target['type'] == 'evm'){ // TODO - are my decimals messed up here?
                // Inbound rate limit is sane
                var inboundRateLimitParams = await target['manager'].getInboundLimitParams(src['chainId'] );
                if(inboundRateLimitParams['limit'].eq(0) || inboundRateLimitParams['limit'].eq(BigNumber.from(2).pow(256).sub(1))){
                    console.log(`WARNING: Inbound rate limit disabled or very high for sender chain ${target_id} and target chain ${src_id}`); 
                }
            }else if(target['type'] == 'solana'){
                var inboundRateLimitParams = (await target['manager'].program.account.inboxRateLimit.fetch(target['manager'].inboxRateLimitAccountAddress(src['chainId'])))['rateLimit'];

                if(inboundRateLimitParams['limit'].eq(0) || inboundRateLimitParams['limit'].eq(BigNumber.from(2).pow(256).sub(1))){
                    console.log(`WARNING: Inbound rate limit disabled or very high for sender chain ${target_id} and target chain ${src_id}`); 
                }
            }

        }
    } 

    // Checking if the mint/burn setup is correct
    if(Object.keys(chainData).length -1 != burn || lock != 1){
        console.log(`ERROR: Bad burn/mint configuration. ${burn} burn chains and ${lock} lock chains`)
    }
    console.log("Finished manager configurations....");

}

async function run(){
    var chainData = await configureChains();
    await checkManagers(chainData);
    //await checkWormholeTranseivers(chainData);
}

run();



// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "wormhole-solidity-sdk/Utils.sol";
import "../src/WormholeEndpointAndManager.sol";

contract DeployWEM is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address tokenAddr = 0xa88085E6370a551Cc046fB6B1E3fB9BE23Ac3a21;
        // ETH SEPOLIA
        Manager.Mode mode = Manager.Mode.LOCKING;
        uint16 sepoliaChainId = 10002;
        address wormholeCoreBridge = 0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78;
        address wormholeRelayer = 0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470;
        // ARB SEPOLIA
        // uint16 sepoliaChainId = 10003;
        // address wormholeCoreBridge = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35;
        // address wormholeRelayer = 0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470;
        // Manager.Mode mode = Manager.Mode.BURNING;
        vm.startBroadcast(deployerPrivateKey);

        WormholeEndpointAndManager impl = new WormholeEndpointAndManager(
            tokenAddr, mode, sepoliaChainId, 1 days, wormholeCoreBridge, wormholeRelayer
        );

        vm.stopBroadcast();
    }
}

contract DeployWEMProxy is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address implementation = 0xCE18952Cd5C47130d4F9fCB0e6E183a3D6237547;
        vm.startBroadcast(deployerPrivateKey);

        WormholeEndpointAndManager proxy =
            WormholeEndpointAndManager(address(new ERC1967Proxy(implementation, "")));
        proxy.initialize();

        vm.stopBroadcast();
    }
}

contract UpgradeWEM is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddr = 0x081d4762aE9D4D51525b8db81865a1691FFA55Ed;
        address newImpl = 0x1e824a19d464d8B30e0c2Ea58e11CB3b077Ccf7F;
        vm.startBroadcast(deployerPrivateKey);

        WormholeEndpointAndManager proxy = WormholeEndpointAndManager(proxyAddr);
        proxy.upgrade(newImpl);

        vm.stopBroadcast();
    }
}

contract RegisterManagerSibling is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddr = 0x081d4762aE9D4D51525b8db81865a1691FFA55Ed;
        // ETH SEPOLIA
        // uint16 siblingChainId = 10002;
        // ARB SEPOLIA
        uint16 siblingChainId = 10003;
        address siblingAddr = 0x081d4762aE9D4D51525b8db81865a1691FFA55Ed;

        vm.startBroadcast(deployerPrivateKey);

        // call setSibling on the manager contract
        WormholeEndpointAndManager proxy = WormholeEndpointAndManager(proxyAddr);
        proxy.setSibling(siblingChainId, toWormholeFormat(siblingAddr));

        vm.stopBroadcast();
    }
}

contract SetManagerLimits is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddr = 0x081d4762aE9D4D51525b8db81865a1691FFA55Ed;
        // ETH SEPOLIA
        uint16 siblingChainId = 10002;
        // ARB SEPOLIA
        // uint16 siblingChainId = 10003;

        vm.startBroadcast(deployerPrivateKey);

        // call setSibling on the manager contract
        WormholeEndpointAndManager proxy = WormholeEndpointAndManager(proxyAddr);
        proxy.setOutboundLimit(type(uint64).max);
        proxy.setInboundLimit(type(uint64).max, siblingChainId);

        vm.stopBroadcast();
    }
}
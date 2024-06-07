load('ext://namespace', 'namespace_create', 'namespace_inject')
load('ext://git_resource', 'git_checkout')

git_checkout('https://github.com/wormhole-foundation/wormhole.git#main', '.wormhole/', unsafe_mode=True)
local(['sed','-i',
    '/{chainId: vaa.ChainIDEthereum, addr: "000000000000000000000000855FA758c77D68a04990E992aA4dcdeF899F654A"},/i'
        +' {chainId: vaa.ChainIDSolana, addr: "8bf0b547c96edc5c1d512ca25c5c1d1812a180438a0046e511d1fb61561d5cdf"},'
        + '{chainId: vaa.ChainIDSolana, addr: "0a490691c21334ca173d9ce386e2a86774ce173f351db10d5d0cccc5c4875376"},'
        + '{chainId: vaa.ChainIDEthereum, addr: "00000000000000000000000042D4BA5e542d9FeD87EA657f0295F1968A61c00A"},'
        + '{chainId: vaa.ChainIDEthereum, addr: "000000000000000000000000b4fFe5983B0B748124577Af4d16953bd096b6897"},'
        + '{chainId: vaa.ChainIDEthereum, addr: "0000000000000000000000003F4E941ef5071a1D09C2eB4a24DA1Fc43F76fcfF"},'
        + '{chainId: vaa.ChainIDBSC, addr: "000000000000000000000000C5aFE31AE505594B190AC71EA689B58139d1C354"},'
        + '{chainId: vaa.ChainIDBSC, addr: "000000000000000000000000e93e3B649d4E01e47dd2170CAFEf0651477649Da"},'
        + '{chainId: vaa.ChainIDBSC, addr: "000000000000000000000000b4fFe5983B0B748124577Af4d16953bd096b6897"},'
    , '.wormhole/node/pkg/accountant/ntt_config.go'])

load(".wormhole/Tiltfile", "namespace", "k8s_yaml_with_ns")

# Copied from .wormhole/Tiltfile, as this setup will extend the `solana-contract` image in order to inject the .so at startup
docker_build(
    ref = "bridge-client",
    context = ".wormhole/",
    only = ["./proto", "./solana", "./clients"],
    dockerfile = ".wormhole/solana/Dockerfile.client",
    # Ignore target folders from local (non-container) development.
    ignore = [".wormhole/solana/*/target"],
)
docker_build(
    ref = "solana-contract",
    context = ".wormhole/solana",
    dockerfile = ".wormhole/solana/Dockerfile",
    target = "builder",
    build_args = {"BRIDGE_ADDRESS": "Bridge1p5gheXUvJ6jGWGeCsgPKgnE3YgdGKRVCMY9o"}
)
# Solana deploy
docker_build(
    ref = "ntt-solana-contract",
    context = "./",
    only = ["./sdk", "./solana"],
    ignore=["./sdk/__tests__", "./sdk/Dockerfile", "./sdk/ci.yaml", "./sdk/**/dist", "./sdk/node_modules", "./sdk/**/node_modules"],
    dockerfile = "./solana/Dockerfile",
)
k8s_yaml_with_ns("./solana/solana-devnet.yaml")
k8s_resource(
    "solana-devnet",
    labels = ["anchor-ntt"],
    port_forwards = [
        port_forward(8899, name = "Solana RPC [:8899]"),
        port_forward(8900, name = "Solana WS [:8900]"),
    ],
)

# EVM build
docker_build(
    ref = "ntt-evm-contract",
    context = "./evm",
    dockerfile = "./evm/Dockerfile",
)

# CI tests
docker_build(
    ref = "ntt-ci",
    context = "./sdk",
    dockerfile = "./sdk/Dockerfile",
)
k8s_yaml_with_ns("./sdk/ci.yaml") 
k8s_resource(
    "ntt-ci-tests",
    labels = ["ntt"],
    resource_deps = ["eth-devnet", "eth-devnet2", "solana-devnet", "guardian", "relayer-engine", "wormchain"],
)

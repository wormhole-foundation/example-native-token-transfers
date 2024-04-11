load('ext://namespace', 'namespace_create', 'namespace_inject')
load('ext://git_resource', 'git_checkout')

git_checkout('https://github.com/wormhole-foundation/wormhole.git#main', '.wormhole/', unsafe_mode=True)
local(['sed','-i','/{chainId: vaa.ChainIDEthereum, addr: "000000000000000000000000855FA758c77D68a04990E992aA4dcdeF899F654A"},/i \\\\t\\t\\t{chainId: vaa.ChainIDSolana, addr: "8bf0b547c96edc5c1d512ca25c5c1d1812a180438a0046e511d1fb61561d5cdf"},\\n\\t\\t\\t{chainId: vaa.ChainIDSolana, addr: "0a490691c21334ca173d9ce386e2a86774ce173f351db10d5d0cccc5c4875376"},\\n\\t\\t\\t{chainId: vaa.ChainIDEthereum, addr: "000000000000000000000000c5afe31ae505594b190ac71ea689b58139d1c354"},\\n\\t\\t\\t{chainId: vaa.ChainIDEthereum, addr: "0000000000000000000000008be8dfcdc90f50562b5022de1f8d83fe93b0b055"},\\n\\t\\t\\t{chainId: vaa.ChainIDBSC, addr: "0000000000000000000000006f84742680311cef5ba42bc10a71a4708b4561d1"},\\n\\t\\t\\t{chainId: vaa.ChainIDBSC, addr: "00000000000000000000000071e7ec880873af0fe33ad988f862be200fdd85cc"},', '.wormhole/node/pkg/accountant/ntt_config.go'])

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

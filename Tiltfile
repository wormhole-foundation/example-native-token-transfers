load('ext://namespace', 'namespace_create', 'namespace_inject')
load('ext://git_resource', 'git_checkout')

git_checkout('https://github.com/wormhole-foundation/wormhole.git#main', '.wormhole/')

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
    context = "./solana/",
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
    context = "./ci_tests",
    dockerfile = "./ci_tests/Dockerfile",
)
k8s_yaml_with_ns("./ci_tests/ci.yaml") 
k8s_resource(
    "ntt-ci-tests",
    labels = ["ntt"],
    resource_deps = ["eth-devnet", "eth-devnet2", "solana-devnet", "guardian", "relayer-engine"],
)

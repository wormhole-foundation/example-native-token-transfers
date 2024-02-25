load('ext://namespace', 'namespace_create')
load('ext://git_resource', 'git_checkout')

git_checkout('https://github.com/wormhole-foundation/wormhole.git#main', '.wormhole/')

load(".wormhole/Tiltfile", "namespace", "k8s_yaml_with_ns")

docker_build(
    ref = "ntt-ci",
    context = ".",
    only = ["./ci_tests"],
    dockerfile = "Dockerfile",
)

k8s_yaml_with_ns("ci.yaml") 

k8s_resource(
    "ntt-ci-tests",
    labels = ["ntt"],
    resource_deps = ["eth-devnet2", "guardian"],
)

load('ext://namespace', 'namespace_create')
load('ext://git_resource', 'git_checkout')

#git_checkout('https://github.com/wormhole-foundation/wormhole.git#main', '.wormhole/',unsafe_mode=True)

# Could modify the ganache layout here?
#load("os", "system")

#os.system("sed -i \"45i \t\t- --allowUnlimitedContractSize=true\" ./.wormhole/devnet/eth-devnet.yaml | sed 's/^[[:blank:]]t//' ./.wormhole/devnet/eth-devnet.yaml > ./.wormhole/devnet/eth-devnet.yaml")

load(".wormhole/Tiltfile", "namespace", "k8s_yaml_with_ns", "set_env_in_jobs", "num_guardians")


# config.clear_enabled_resources()
# config.set_enabled_resources([ 
#     "guardian", 
#     "spy",
#     "eth-devnet",
#     "eth-devnet2"
# ])
namespace_create(namespace, allow_duplicates=True)

# Build the container
docker_build(
    ref = "ntt-setup",
    context = ".",
    dockerfile = "./Dockerfile-ntt",
    ignore=[""] # TODO - don't take in the lib but generate dynamically. Tilt won't grab the .git by default and I don't know how to get around this. More on this issue at https://github.com/tilt-dev/tilt/issues/2169.
    #target = "build",
    #ignore=["./sdk/js", "./relayer"]
)

# # Deploy pod for deploying then testing ntt token
k8s_yaml_with_ns("./ntt.yaml") 

k8s_resource(
    "ntt-test",
    #resource_deps = ["eth-dev"], # TODO - don't want the whole thing to recompile so I'm keeping this for rn.
    labels = ["ntt"],
 )
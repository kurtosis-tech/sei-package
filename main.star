SEI_IMAGE = "sei-chain/localnode"
SEI_NODE_PREFIX = "node"

DEFAULT_CLUSTER_SIZE = 4
DEFAULT_NUM_ACCOUNTS = 10

MAIN_BASE = "/sei-protocol/"
MAIN_DIR = MAIN_BASE + "sei-chain/"


def run(plan , args):

    cluster_size = args.get("cluster_size", DEFAULT_CLUSTER_SIZE)
    num_accounts = args.get("num_accounts", DEFAULT_NUM_ACCOUNTS)

    node_names = []
    genesis_accounts = []

    configurer = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/configurer.sh")

    built = build(plan)

    for index in range(0, cluster_size+1):
        env_vars_for_node = {}
        env_vars_for_node["ID"] = str(index)
        env_vars_for_node["CLUSTER_SIZE"] = str(cluster_size)
        env_vars_for_node["NUM_ACCOUNTS"] = str(num_accounts)


        config = ServiceConfig(
            image = SEI_IMAGE,
            env_vars = env_vars_for_node,
            ports = {
                "prometheus": PortSpec(number = 9090, wait = None),
                "grpc-web": PortSpec(number = 9091, wait = None),
                "tendermint-p2p": PortSpec(number = 26656, wait = None),
                "tendermint-rpc": PortSpec(number = 26657, wait = None),
                "abci-app": PortSpec(number = 26658, wait = None)
            },
            files = {
                MAIN_BASE: built,
                "/tmp/configurer": configurer
            },
            entrypoint = ["sleep", "9999999"]
        )

        name = SEI_NODE_PREFIX + str(index)

        plan.add_service(
            name = name,
            config = config,
        )

        plan.exec(
            service_name = name,
            recipe = ExecRecipe(
                command = ["mkdir", "/root/go/bin"],
            )
        )

        plan.exec(
            service_name = name,
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", "go install github.com/CosmWasm/wasmvm"]
            )            
        )

        plan.exec(
            service_name = name,
            recipe = ExecRecipe(
                command = ["/tmp/configurer/configurer.sh"]
            )            
        )


        account = read_file(name, "build/generated/genesis_accounts.txt")
        peers = read_file(name, "build/generated/persistent_peers.txt")

        genesis_accounts.append(output)
        node_names.append(name)

    # store all build/generated/persistent_peers.txt
    # build/generated/genesis_accounts.txt
    # on apic
    # and keys
    # upload concatenated genesis_accounts & all exported keys to node 0
    # upload all persistent peers everywhere after concatenating them & upload via exec

    # run step 2 & 3
    # copy over the genesis.json from node 0 to everywhere to the right place

    # run step 4, 5 & 6 on all nodes in any order


def read_file(service_name, filename):
    output = plan.exec(
        service_name = name,
        recipe = ExecRecipe(
            command = ["cat", filename]
        )
    )
    return output["output"]


# This builds everything and we throw this away
def build(plan):
    cloner = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/cloner.sh")
    builder = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/builder.sh")

    plan.add_service(
        name = "builder",
        config = ServiceConfig(
            image = SEI_IMAGE,
            entrypoint = ["sleep", "999999"],
            files = {
                "/tmp/cloner": cloner,
                "/tmp/builder": builder,
            },
        ),
    )

    plan.exec(
        service_name = "builder",
        recipe = ExecRecipe(
            command = ["/tmp/cloner/cloner.sh"],
        )        
    )

    plan.exec(
        service_name = "builder",
        recipe = ExecRecipe(
            command = ["date"],
        )        
    )

    plan.exec(
        service_name = "builder",
        recipe = ExecRecipe(
            command = ["/tmp/builder/builder.sh"],
        )        
    )

    plan.exec(
        service_name = "builder",
        recipe = ExecRecipe(
            command = ["date"],
        )        
    )

    built = plan.store_service_files(
        service_name = "builder",
        src = MAIN_DIR
    )

    return built
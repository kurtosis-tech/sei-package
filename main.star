SEI_IMAGE = "sei-chain/localnode"
SEI_NODE_PREFIX = "node"

DEFAULT_CLUSTER_SIZE = 4
DEFAULT_NUM_ACCOUNTS = 10

MAIN_BASE = "/sei-protocol/"
MAIN_DIR = MAIN_BASE + "sei-chain/"

PERSISTENT_PEERS_PATH = "build/generated/persistent_peers.txt"
GENESIS_ACCOUNTS_PATH = "build/generated/genesis_accounts.txt"
EXPORTED_KEYS_PATH = "build/generated/exported_keys/"

ZEROTH_NODE = 0

def run(plan , args):

    cluster_size = args.get("cluster_size", DEFAULT_CLUSTER_SIZE)
    num_accounts = args.get("num_accounts", DEFAULT_NUM_ACCOUNTS)

    node_names = []
    genesis_accounts = []
    peers = []

    configurer = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/configurer.sh")

    built = build(plan)

    for index in range(0, cluster_size):
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


        node_names.append(name)


    for name in node_names:

        plan.exec(
            service_name = name,
            recipe = ExecRecipe(
                command = ["/tmp/configurer/configurer.sh"]
            )
        )


        account = read_file_from_service(plan, name, GENESIS_ACCOUNTS_PATH)
        peer = read_file_from_service(plan, name, PERSISTENT_PEERS_PATH)

        genesis_accounts.append(account)
        peers.append(peer)


    write_together_node0(plan, genesis_accounts, GENESIS_ACCOUNTS_PATH)
    read_file_from_service_with_nl(plan, node_names[ZEROTH_NODE], GENESIS_ACCOUNTS_PATH)

    write_together_node0(plan, peers, PERSISTENT_PEERS_PATH)
    read_file_from_service_with_nl(plan, node_names[ZEROTH_NODE], PERSISTENT_PEERS_PATH)

    copy_file_in_dir(plan, source_service_name, dir_name, target_service_name, target_dir_name)

    for node in node_names[1:]:
        copy_file_in_dir(plan, EXPORTED_KEYS_PATH, node_names[ZEROTH_NODE], EXPORTED_KEYS_PATH)

    plan.exec(
        node_names[ZEROTH_NODE],
        command = ["ls", EXPORTED_KEYS_PATH]
    )

    # run step 2 & 3
    # copy over the genesis.json from node 0 to everywhere to the right place

    # run step 4, 5 & 6 on all nodes in any order


# this assumes there is only one file in that dir
def copy_file_in_dir(plan, source_service_name, dir_name, target_service_name, target_dir_name)):
    filename_response = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["ls", dir_name]
        )
    )

    filename = filename_response["output"]
    filedata = read_file_from_service(source_service_name, dir_name + filename_response)

    write_together_node0


def read_file_from_service(plan, service_name, filename):
    output = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "cat {} | tr -d '\n'".format(filename)]
        )
    )
    return output["output"]


def read_file_from_service_with_nl(plan, service_name, filename):
    output = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "cat {}".format(filename)]
        )
    )
    return output["output"]



def write_together_node0(plan, lines, filename):
    for line in lines[1:]:
        plan.exec(
            service_name = "node0",
            recipe = ExecRecipe(command = ["/bin/sh", "-c", 'echo "{0}" >> {1}'.format(line, filename)])
        )


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
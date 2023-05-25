SEI_IMAGE = "sei-chain/localnode"
SEI_NODE_PREFIX = "node"

DEFAULT_CLUSTER_SIZE = 4
DEFAULT_NUM_ACCOUNTS = 10

MAIN_BASE = "/sei-protocol/"
MAIN_DIR = MAIN_BASE + "sei-chain/"

PERSISTENT_PEERS_PATH = "build/generated/persistent_peers.txt"
GENESIS_ACCOUNTS_PATH = "build/generated/genesis_accounts.txt"
EXPORTED_KEYS_PATH = "build/generated/exported_keys/"
GENESIS_JSON_PATH = "build/generated/genesis.json"

ZEROTH_NODE = 0

def run(plan , args):

    cluster_size = args.get("cluster_size", DEFAULT_CLUSTER_SIZE)
    num_accounts = args.get("num_accounts", DEFAULT_NUM_ACCOUNTS)

    node_names = []
    genesis_accounts = []
    peers = []

    configurer = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/configurer.sh")
    genesis = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/genesis.sh")
    step45 = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/step_4_and_5.sh")
    step6 = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/step_6.sh")

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
                "/tmp/configurer": configurer,
                "/tmp/genesis": genesis,
                "/tmp/step45": step45,
                "/tmp/step6": step6,
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


    # copy over genesis accounts to node0
    write_together_node0(plan, genesis_accounts, GENESIS_ACCOUNTS_PATH)
    read_file_from_service_with_nl(plan, node_names[ZEROTH_NODE], GENESIS_ACCOUNTS_PATH)

    # copy over persistent peers to node 0
    combine_file_over_nodes(plan, node_names, peers, PERSISTENT_PEERS_PATH)    

    # copy over exported keys to node 0
    for source_node in node_names[1:]:
        copy_only_file_in_dir(plan, EXPORTED_KEYS_PATH, source_node, EXPORTED_KEYS_PATH, node_names[ZEROTH_NODE])
    
    # verify exported keys
    plan.exec(
        service_name = node_names[ZEROTH_NODE],
        recipe = ExecRecipe(
            command = ["ls", EXPORTED_KEYS_PATH],
        )
    )

    # run step 2 & 3 on zero'th node
    plan.exec(
        service_name = node_names[ZEROTH_NODE],
        recipe = ExecRecipe(
            command = ["/tmp/genesis/genesis.sh"],
        )
    )

    copy_genesis_json_to_other_nodes(plan, node_names)
    
    # run step 4 and 5 everywhere
    for name in node_names:
        plan.exec(
            service_name = name,
            recipe = ExecRecipe(
                command = ["/tmp/step45/step_4_and_5.sh"]
            )
        )

    # run step 6 after 4 & 5 are done at both places
    for name in node_names:
        plan.exec(
            service_name = name,
            recipe = ExecRecipe(
                command = ["/tmp/step6/step_6.sh"]
            )
        )


def copy_genesis_json_to_other_nodes(plan, node_names):
    plan.exec(
        service_name = node_names[ZEROTH_NODE],
        recipe = ExecRecipe(
            command = ["mkdir", "-p", "/tmp/genesis_json/"]
        )        
    )    
    plan.exec(
        service_name = node_names[ZEROTH_NODE],
        recipe = ExecRecipe(
            command = ["cp", GENESIS_JSON_PATH, "/tmp/genesis_json/"]
        )        
    )
    for target_node in node_names[1:]:
        copy_only_file_in_dir(plan, node_names[ZEROTH_NODE], "/tmp/genesis_json/", target_node, "build/generated/")


def copy_only_file_in_dir(plan, source_service_name, dir_name, target_service_name, target_dir_name):
    filename_response = plan.exec(
        service_name = source_service_name,
        recipe = ExecRecipe(
            command = ["ls", dir_name]
        )
    )

    filename = filename_response["output"]
    filedata = read_file_from_service(plan, source_service_name, dir_name + filename)

    plan.exec(
        service_name = source_service_name,
        recipe = ExecRecipe(command = ["/bin/sh", "-c", 'echo "{0}" > {1}{2}'.format(filedata, target_dir_name, filename)])
    )

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


def combine_file_over_nodes(plan, node_names, lines, filename):
    for index, target_node_name in enumerate(node_names):
        for line in lines[0:index] + lines[index+1:]:
            plan.exec(
                service_name = target_node_name,
                recipe = ExecRecipe(command = ["/bin/sh", "-c", 'echo "{0}" >> {1}'.format(line, filename)])
            )
        # we verify things were properly written
        read_file_from_service_with_nl(plan, target_node_name, filename)

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
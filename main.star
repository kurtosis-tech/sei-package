SEI_IMAGE = "sei-chain/localnode"
SEI_PUBLISHED_IMAGE = "h4ck3rk3y/localnode:3.0.1"
SEI_NODE_PREFIX = "node"
SEI_DEFAULT_GIT_TAG = "3.0.1"

DEFAULT_CLUSTER_SIZE = 4
DEFAULT_NUM_ACCOUNTS = 10

MAIN_BASE = "/sei-protocol/"
MAIN_DIR = MAIN_BASE + "sei-chain/"

PERSISTENT_PEERS_PATH = "build/generated/persistent_peers.txt"
GENESIS_ACCOUNTS_PATH = "build/generated/genesis_accounts.txt"
EXPORTED_KEYS_PATH = "build/generated/exported_keys/"
GENESIS_JSON_PATH = "build/generated/genesis.json"
GENTX_PATH = "build/generated/gentx/"

ZEROTH_NODE = 0

def run(plan , args):
    image = args.get("image", SEI_PUBLISHED_IMAGE)
    git_tag = args.get("git_tag", SEI_DEFAULT_GIT_TAG)

    builds_image_live = args.get("builds_image_live", False)
    if builds_image_live:
        image = SEI_IMAGE

    cluster_size = args.get("cluster_size", DEFAULT_CLUSTER_SIZE)
    num_accounts = args.get("num_accounts", DEFAULT_NUM_ACCOUNTS)

    node_names = []
    genesis_accounts = []
    peers = []

    configurer = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/configurer.sh")
    genesis = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/genesis.sh")
    step45 = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/step_4_and_5.sh")
    step6 = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/step_6.sh")

    built = build(plan, image, builds_image_live)

    for index in range(0, cluster_size):
        env_vars_for_node = {}
        env_vars_for_node["ID"] = str(index)
        env_vars_for_node["CLUSTER_SIZE"] = str(cluster_size)
        env_vars_for_node["NUM_ACCOUNTS"] = str(num_accounts)


        config = ServiceConfig(
            image = image,
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
    plan.print("Copying over genesis accounts to {0}".format(node_names[ZEROTH_NODE]))
    write_together_node0(plan, genesis_accounts, GENESIS_ACCOUNTS_PATH)
    read_file_from_service_with_nl(plan, node_names[ZEROTH_NODE], GENESIS_ACCOUNTS_PATH)

    # copy over persistent peers to node 0
    plan.print("Concatenating {0} on all nodes".format(PERSISTENT_PEERS_PATH))
    combine_file_over_nodes(plan, node_names, peers, PERSISTENT_PEERS_PATH)

    # copy over exported keys to node 0
    plan.print("Copying over all exported_keys to {0}".format(node_names[ZEROTH_NODE]))
    for source_node in node_names[1:]:
        copy_only_file_in_dir(plan, source_node, EXPORTED_KEYS_PATH, node_names[ZEROTH_NODE], EXPORTED_KEYS_PATH)

    # copy over gentx to node 0
    plan.print("Copying over all gentx to {0}".format(node_names[ZEROTH_NODE]))
    for source_node in node_names[1:]:
        copy_only_file_in_dir(plan, source_node, GENTX_PATH, node_names[ZEROTH_NODE], GENTX_PATH)

    # verify exported keys
    plan.print("Verifying exported keys on {0}".format(node_names[ZEROTH_NODE]))
    plan.exec(
        service_name = node_names[ZEROTH_NODE],
        recipe = ExecRecipe(
            command = ["ls", EXPORTED_KEYS_PATH],
        )
    )

    # run step 2 & 3 on zero'th node
    plan.print("Running Genesis on {0}".format(node_names[ZEROTH_NODE]))
    plan.exec(
        service_name = node_names[ZEROTH_NODE],
        recipe = ExecRecipe(
            command = ["/tmp/genesis/genesis.sh"],
        )
    )

    copy_genesis_json_to_other_nodes(plan, node_names)

    # run step 4 and 5 everywhere
    for name in node_names:
        plan.print("Running SIED node on {0}".format(name))
        plan.exec(
            service_name = name,
            recipe = ExecRecipe(
                command = ["/tmp/step45/step_4_and_5.sh"]
            )
        )

    plan.print("Waiting for tendermint rpc port to be alive on every node before running price feeder")
    wait_on_tendermint_rpc(plan, node_names)

    # run step 6 after 4 & 5 are done at both places
    for name in node_names:
        plan.print("Running price feeder on node {0}".format(name))
        plan.exec(
            service_name = name,
            recipe = ExecRecipe(
                command = ["/tmp/step6/step_6.sh"]
            )
        )


    plan.print("We wait for 20 seconds to make sure that the price feeder is healthy")
    plan.exec(
        service_name = node_names[ZEROTH_NODE],
        recipe = ExecRecipe(
            command = ["sleep", "20"]
        )
    )

    print_some_logs(plan, node_names)


# print some logs on each node
def wait_on_tendermint_rpc(plan, node_names):
    request_recipe  = GetHttpRequestRecipe(
        port_id = "tendermint-rpc",
        endpoint = "/",
    )
    for name in node_names:
        plan.wait(
            service_name=name,
            recipe=request_recipe,
            field="code",
            assertion="==",
            target_value=200,
        )

# print some logs on each node
def print_some_logs(plan, node_names):
    for index, node in enumerate(node_names):
        plan.exec(
            service_name = node,
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", "tail -n 20 build/generated/logs/seid-{0}.log".format(index)]
            )
        )
        plan.exec(
            service_name = node,
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", "tail -n 20 build/generated/logs/price-feeder-{0}.log".format(index)]
            )
        )


# copies genesis.json from node0 to all other nodes
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


# copies the only file in source dir to the target dir preserving its name
def copy_only_file_in_dir(plan, source_service_name, dir_name, target_service_name, target_dir_name):
    filename_response = plan.exec(
        service_name = source_service_name,
        recipe = ExecRecipe(
            command = ["ls", dir_name]
        )
    )

    filename = filename_response["output"]
    filedata = read_file_from_service_with_nl(plan, source_service_name, dir_name + filename)

    plan.exec(
        service_name = target_service_name,
        recipe = ExecRecipe(command = ["/bin/sh", "-c", "echo -n '{0}' > {1}{2}".format(filedata, target_dir_name, filename)])
    )

    read_file_from_service_with_nl(plan, target_service_name, "{}{}".format(target_dir_name, filename))


# reads the given file in service without the new line
def read_file_from_service(plan, service_name, filename):
    output = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "cat {} | tr -d '\n'".format(filename)]
        )
    )
    return output["output"]


# reads the given file from service with new lines
def read_file_from_service_with_nl(plan, service_name, filename):
    output = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "cat {}".format(filename)]
        )
    )
    return output["output"]


# writes a given file on multiple nodes into one file on node0
def write_together_node0(plan, lines, filename):
    for line in lines[1:]:
        plan.exec(
            service_name = "node0",
            recipe = ExecRecipe(command = ["/bin/sh", "-c", 'echo "{0}" >> {1}'.format(line, filename)])
        )


# combines a file distributed accross nodes to a new file on node0
def combine_file_over_nodes(plan, node_names, lines, filename):
    for index, target_node_name in enumerate(node_names):
        for line in lines[0:index] + lines[index+1:]:
            plan.exec(
                service_name = target_node_name,
                recipe = ExecRecipe(command = ["/bin/sh", "-c", 'echo "{0}" >> {1}'.format(line, filename)])
            )
        # we verify things were properly written
        read_file_from_service_with_nl(plan, target_node_name, filename)


# This builds the binary and we throw this away
def build(plan, image, builds_image_live, git_tag):
    cloner = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/cloner.sh")
    builder = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/builder.sh")

    plan.add_service(
        name = "builder",
        config = ServiceConfig(
            image = image,
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

    if not builds_image_live:
        plan.exec(
            service_name = "builder",
            recipe = ExecRecipe(
                command = ["git", "checkout", git_tag]
            )
        )

    # remove the .git folder to trim down the directory
    plan.exec(
        service_name = "builder",
        recipe = ExecRecipe(
            command = ["rm", "-rf", ".git"]
        )
    )

    plan.exec(
        service_name = "builder",
        recipe = ExecRecipe(
            command = ["/tmp/builder/builder.sh"],
        )
    )

    built = plan.store_service_files(
        service_name = "builder",
        src = MAIN_DIR
    )

    plan.remove_service("builder")

    return built
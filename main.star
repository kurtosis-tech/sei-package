SEI_IMAGE = "sei-chain/localnode"
SEI_NODE_PREFIX = "node"

DEFAULT_CLUSTER_SIZE = 4
DEFAULT_NUM_ACCOUNTS = 10


def run(plan , args):

    cluster_size = args.get("cluster_size", DEFAULT_CLUSTER_SIZE)
    num_accounts = args.get("num_accounts", DEFAULT_NUM_ACCOUNTS)

    # cloned = clone_container(plan)

    for index in range(0, cluster_size):
        env_vars_for_node = {}
        env_vars_for_node["ID"] = str(index)
        env_vars_for_node["CLUSTER_SIZE"] = str(cluster_size)
        env_vars_for_node["NUM_ACCOUNTS"] = str(num_accounts)

        entrypoint = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/entrypoint.sh")

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
                "/tmp/": entrypoint,
            },
            cmd = ["/tmp/entrypoint.sh"]
        )

        plan.add_service(
            name = SEI_NODE_PREFIX + str(index),
            config = config,
        )


def clone_container(plan):
    plan.add_service(
        name = "cloner",
        config = ServiceConfig(
            image = "alpine/git",
            entrypoint = ["sleep", "999999"]
        )
    )

    plan.exec(
        service_name = "cloner",
        recipe = ExecRecipe(
            command = ["git", "clone", "https://github.com/sei-protocol/sei-chain", "/tmp/sei-chain"]
        )
    )

    cloned = plan.store_service_files(
        service_name = "cloner",
        src = "/tmp/sei-chain"
    )

    return cloned
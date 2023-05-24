SEI_IMAGE = "sei-chain/localnode"
SEI_NODE_PREFIX = "node"

DEFAULT_CLUSTER_SIZE = 4
DEFAULT_NUM_ACCOUNTS = 10


def run(plan , args):

    cluster_size = args.get("cluster_size", DEFAULT_CLUSTER_SIZE)
    num_accounts = args.get("num_accounts", DEFAULT_NUM_ACCOUNTS)

    built = launch_builder(plan, cluster_size)

    for index in range(0, cluster_size+1):
        env_vars_for_node = {}
        env_vars_for_node["ID"] = str(index)
        env_vars_for_node["CLUSTER_SIZE"] = str(cluster_size)
        env_vars_for_node["NUM_ACCOUNTS"] = str(num_accounts)

        entrypoint = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/entrypoint.sh")

        config = ServiceConfig(
            image = SEI_IMAGE,
            env_vars = env_vars_for_node,
            ports = {
                "prometheus": PortSpec(number = 9090, wait = "6000s"),
                "grpc-web": PortSpec(number = 9091, wait = None),
                "tendermint-p2p": PortSpec(number = 26656, wait = None),
                "tendermint-rpc": PortSpec(number = 26657, wait = None),
                "abci-app": PortSpec(number = 26658, wait = None)
            },
            files = {
                "/sei-protocol/": built,
                "/tmp/": entrypoint,
            },
            cmd = ["/tmp/entrypoint.sh"]
        )

        plan.add_service(
            name = SEI_NODE_PREFIX + str(index),
            config = config,
        )


# This builds everything and we throw this away
def launch_builder(plan, cluster_size):
    cloner = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/cloner.sh")
    configurer = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/configurer.sh")
    genesis = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/genesis.sh")
    builder = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/builder.sh")

    plan.add_service(
        name = "builder",
        config = ServiceConfig(
            image = SEI_IMAGE,
            entrypoint = ["sleep", "999999"],
            files = {
                "/tmp/cloner": cloner,
                "/tmp/configurer": configurer,
                "/tmp/genesis": genesis,
                "/tmp/builder": builder,
            },
            env_vars = {
                "CLUSTER_SIZE": str(cluster_size)
            }
        ),
    )

    plan.exec(
        service_name = "builder",
        recipe = ExecRecipe(
            command = ["/tmp/cloner/cloner.sh"]
        )
    )

    plan.exec(
        service_name = "builder",
        recipe = ExecRecipe(
            command = ["/tmp/builder/builder.sh"]
        )
    )

    # we need to generate a genesis account per node
    for index in range(0, cluster_size):
        plan.exec(
            service_name = "builder",
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", "ID={0} /tmp/configurer/configurer.sh".format(index)]
            )
        )

    plan.exec(
        service_name = "builder",
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "ID=0 /tmp/genesis/genesis.sh"]
        )
    )

    built = plan.store_service_files(
        service_name = "builder",
        src = "/sei-protocol/sei-chain"
    )

    plan.remove_service("builder")

    return built
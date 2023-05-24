SEI_IMAGE = "sei-chain/localnode"
SEI_NODE_PREFIX = "node"

DEFAULT_CLUSTER_SIZE = 4
DEFAULT_NUM_ACCOUNTS = 10


def run(plan , args):

    cluster_size = args.get("cluster_size", DEFAULT_CLUSTER_SIZE)
    num_accounts = args.get("num_accounts", DEFAULT_NUM_ACCOUNTS)

    for index in range(0, cluster_size):
        env_vars_for_node = {}
        env_vars_for_node["ID"] = str(index)
        env_vars_for_node["CLUSTER_SIZE"] = str(cluster_size)
        env_vars_for_node["SKIP_BUILD"] = "false"
        env_vars_for_node["NUM_ACCOUNTS"] = str(num_accounts)

        config = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/config")

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
                "/sei-protocol/sei-chain/docker/localnode/config": config,
            }
        )

        plan.add_service(
            name = SEI_NODE_PREFIX + str(index),
            config = config,
        )


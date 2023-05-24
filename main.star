SEI_IMAGE = "sei-chain/localnode"
SEI_NODE_PREFIX = "node"

DEFAULT_CLUSTER_SIZE = 4
DEFAULT_NUM_ACCOUNTS = 10


def plan(run , args):

    cluster_size = args.get("cluster_size", DEFAULT_CLUSTER_SIZE)
    num_accounts = args.get("num_accounts", DEFAULT_NUM_ACCOUNTS)

    for index in range(0, cluster_size):
        env_vars_for_node = {}
        env_vars_for_node["ID"] = str(index)
        env_vars_for_node["CLUSTER_SIZE"] = str(cluster_size)
        env_vars_for_node["SKIP_BUILD"] = "true"
        env_vars_for_node["NUM_ACCOUNTS"] = str(num_accounts)
        config = ServiceConfig(
            image = SEI_IMAGE,
            env_vars = env_vars_for_node
            ports = {
                "prometheus": PortSpec(number = 9090),
                "grpc-web": PortSpec(number = 9091),
                "tendermint-p2p": PortSpec(number = 26656),
                "tendermint-rpc": PortSpec(number = 26657),
                "abci-app": PortSpec(number = 26658)
            }
        )

        plan.add_service(
            name = node + str(index),
            config = config,
        )


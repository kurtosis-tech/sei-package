SEI_IMAGE = "sei-chain/localnode"
SEI_NODE_PREFIX = "node"

DEFAULT_CLUSTER_SIZE = 4
DEFAULT_NUM_ACCOUNTS = 10

MAIN_DIR = "/sei-protocol/sei-chain/"


def run(plan , args):

    cluster_size = args.get("cluster_size", DEFAULT_CLUSTER_SIZE)
    num_accounts = args.get("num_accounts", DEFAULT_NUM_ACCOUNTS)

    node_names = []

    cloner = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/cloner.sh")
    configurer = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/configurer.sh")

    sied, price_feeder = build(plan, cloner)

    for index in range(0, cluster_size+1):
        env_vars_for_node = {}
        env_vars_for_node["ID"] = str(index)
        env_vars_for_node["CLUSTER_SIZE"] = str(cluster_size)
        env_vars_for_node["NUM_ACCOUNTS"] = str(num_accounts)


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
                "/tmp/cloner": cloner,
                "/tmp/sied": sied,
                "/tmp/feeder": price_feeder
                "/tmp/configurer": configurer,
            },
            cmd = ["/tmp/cloner/cloner.sh"]
        )

        name = SEI_NODE_PREFIX + str(index)        

        plan.add_service(
            name = name,
            config = config,
        )

        plan.exec(
            service_name = name,
            command = ["mv", "/tmp/sied/sied", MAIN_DIR + "/build/" + "seid"],
        )

        plan.exec(
            service_name = name,
            command = ["mv", "/tmp/feeder/price-feeder", MAIN_DIR + "/build/" + "price-feeder"],
        )

        nodes = node_names.append(name)
    
    for node in node_names:
        output = plan.exec(
            service_name = node,
            command = ["/tmp/configurer/configurer.sh"]
        )

        plan.print(output)


# This builds everything and we throw this away
def build(plan, cloner):
    builder = plan.upload_files("github.com/kurtosis-tech/sei-package/static_files/builder.sh")

    plan.add_service(
        name = "builder",
        config = ServiceConfig(
            image = SEI_IMAGE,
            entrypoint = ["sleep", "999999"],
            files = {
                "/tmp/cloner": cloenr
                "/tmp/builder": builder,
            },
            env_vars = {
                "CLUSTER_SIZE": str(cluster_size)
            }
        ),
    )

    plan.exec(
        service_name = "builder",
        command = ["/tmp/cloner/cloner.sh"]
    )

    plan.exec(
        service_name = "builder",
        command = ["/tmp/builder/build.sh"]
    )

    sied = plan.store_service_files(
        service_name = "node0",
        src = MAIN_DIR + "/build/seid"
    )

    price_feeder = plan.store_service_files(
        service_name = "node0",
        src = MAIN_DIR + "/build/price_feeder"
    )


    return sied, price_feeder

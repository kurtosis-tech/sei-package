# SEI Package

This allows you to spin up an N node SEI cluster and price feeders. To run it you need to have Kurtosis installed;

```bash
kurtosis run github.com/kurtosis-tech/sei-package
```

By default this starts a 4 node cluster with 10 accounts each; you can change it to however many you like by passing
arguments like -

```bash
kurtosis run github.com/kurtosis-tech/sei-package '{"cluster_size": 4, "num_accounts": 10}'
```

This starts the SEI node and the price feeder on each node